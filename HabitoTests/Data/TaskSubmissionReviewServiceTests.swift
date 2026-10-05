import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("家长通过与退回原子事务")
struct TaskSubmissionReviewServiceTests {
    @Test("次日通过仍按原提交自主边界，奖励按原快照且真实入账在审核时", arguments: [-1.0, 0.0, 1.0])
    func nextDayApprovalUsesOriginalSnapshot(offset: TimeInterval) throws {
        let setup = try makeSetup(offset: offset)
        setup.occurrence.scheduledAt = setup.now.addingTimeInterval(-86400)
        setup.occurrence.xpRewardSnapshot = 999
        setup.occurrence.coinRewardSnapshot = 999
        setup.occurrence.activeBonusCoinSnapshot = 999
        setup.occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.selfConfirm.rawValue
        try setup.context.save()
        let reviewedAt = setup.now.addingTimeInterval(86400)
        let receipt = try TaskSubmissionReviewService(context: setup.context).approve(
            setup.occurrence, submissionID: setup.submissionID, at: reviewedAt)
        let record = try #require(setup.occurrence.completionRecord)
        #expect(receipt.didReview && receipt.state == .approved && !receipt.rewardIsRevoked)
        #expect(receipt.xp == 11 && receipt.coins == (offset < 0 ? 10 : 7))
        #expect(receipt.timing == (offset < 0 ? .beforeReminder : .afterReminder))
        #expect(record.completedAt == setup.now.addingTimeInterval(offset) && record.rewardSettledAt == reviewedAt)
        #expect(record.submissionID == setup.submissionID && record.rewardSettlementVersion == 2)
        #expect(record.completionSource == .parentApproval && record.activeDurationSeconds == 30)
        #expect(setup.occurrence.status == .completed && record.createdAt == reviewedAt)
        let ledger = try TaskCompletionAuditValidator(context: setup.context).validate(record)
        #expect(ledger.xp[RewardLedgerKey.xpReward(record.id)]?.createdAt == reviewedAt)
        #expect(ledger.coin[RewardLedgerKey.coinReward(record.id)]?.createdAt == reviewedAt)
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
    }

    @Test("零奖励通过仍生成已知自主事实与成对零交易")
    func zeroRewardApprovalIsKnownAndSettled() throws {
        let setup = try makeSetup(zero: true)
        let result = try TaskSubmissionReviewService(context: setup.context).approve(
            setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        #expect(result.didReview && result.timing == .beforeReminder && result.xp == 0 && result.coins == 0)
        #expect(try setup.context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
        #expect(try setup.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 1)
    }

    @Test("重复通过返回原时间和完成 ID，不再次保存或发奖")
    func approvalRetryReturnsOriginalReceipt() throws {
        let setup = try makeSetup()
        let first = try TaskSubmissionReviewService(context: setup.context).approve(
            setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        let retry = try TaskSubmissionReviewService(
            context: setup.context, saveChanges: { _ in Issue.record("幂等不应保存") }
        ).approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(86400))
        #expect(!retry.didReview && retry.completionID == first.completionID && retry.reviewedAt == first.reviewedAt)
        #expect(try setup.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
    }

    @Test("退回无奖励且保留计时，重提新快照；旧退回请求不误审新提交")
    func returnAndResubmitKeepsHistoryAndRejectsOldApproval() throws {
        let setup = try makeSetup()
        let review = TaskSubmissionReviewService(context: setup.context)
        let first = try review.returnForRevision(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        #expect(
            first.didReview && first.state == .returned && first.completionID == nil && first.xp == 0
                && first.coins == 0)
        try expectNoReward(setup.context)
        #expect(
            setup.occurrence.status == .pending && setup.occurrence.timerSessions.first?.accumulatedActiveSeconds == 30)
        setup.occurrence.xpRewardSnapshot = 13
        setup.occurrence.scheduledAt = setup.now.addingTimeInterval(100)
        try setup.context.save()
        _ = try TaskProgressService(context: setup.context).startTiming(
            for: setup.occurrence, at: setup.now.addingTimeInterval(1))
        let next = try TaskSubmissionService(context: setup.context).submit(
            setup.occurrence, at: setup.now.addingTimeInterval(11))
        let retry = try review.returnForRevision(
            setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(12))
        #expect(!retry.didReview && retry.reviewedAt == setup.now)
        #expect(throws: TaskSubmissionReviewError.conflictingOutcome(setup.submissionID)) {
            try review.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(12))
        }
        let rows = try TaskSubmissionHistory(context: setup.context).records(for: setup.occurrence.id)
        #expect(rows.count == 2 && rows.first?.reviewState == .returned && rows.last?.reviewState == .waiting)
        #expect(next.activeDurationSeconds == 40)
        let approved = try review.approve(
            setup.occurrence, submissionID: next.submissionID, at: setup.now.addingTimeInterval(12))
        #expect(approved.xp == 13 && approved.coins == 10 && approved.timing == .beforeReminder)
        #expect(setup.occurrence.completionRecord?.activeDurationSeconds == 40)
    }

    @Test("通过后不能改成退回，错误 ID 不指向最新提交")
    func conflictingAndUnknownRequestsCannotReview() throws {
        let setup = try makeSetup()
        let review = TaskSubmissionReviewService(context: setup.context)
        let unknownID = V0MigrationFixture.orphanID
        #expect(throws: TaskSubmissionReviewError.submissionNotFound(unknownID)) {
            try review.approve(setup.occurrence, submissionID: unknownID, at: setup.now)
        }
        _ = try review.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        #expect(throws: TaskSubmissionReviewError.conflictingOutcome(setup.submissionID)) {
            try review.returnForRevision(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        }
        #expect(setup.occurrence.status == .completed && !setup.context.hasChanges)
    }

    @Test("已冲正的原通过重试不补发，也不改后来新的等待事实")
    func revokedApprovalRetryDoesNotGrantAgain() throws {
        let setup = try makeSetup()
        let review = TaskSubmissionReviewService(context: setup.context)
        let approved = try review.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        let completionID = try #require(approved.completionID)
        _ = try TaskCompletionUndoService(context: setup.context).undo(
            setup.occurrence, completionID: completionID, at: setup.now.addingTimeInterval(1))
        let next = try TaskSubmissionService(context: setup.context).submit(
            setup.occurrence, at: setup.now.addingTimeInterval(2))
        let retry = try review.approve(
            setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(3))
        #expect(!retry.didReview && retry.rewardIsRevoked && retry.completionID == completionID)
        #expect(setup.occurrence.status == .pending && setup.occurrence.completionRecord == nil)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        #expect(
            try TaskSubmissionHistory(context: setup.context).records(for: setup.occurrence.id).last?.id
                == next.submissionID)
        #expect(try setup.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        #expect(try setup.context.fetchCount(FetchDescriptor<XPTransaction>()) == 2)
        let secondApproval = try review.approve(
            setup.occurrence, submissionID: next.submissionID, at: setup.now.addingTimeInterval(3))
        let oldRetry = try review.approve(
            setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(4))
        #expect(!oldRetry.didReview && oldRetry.rewardIsRevoked && oldRetry.completionID == completionID)
        #expect(setup.occurrence.completionRecord?.id == secondApproval.completionID)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 11, coins: 7))
    }

    @Test("审核早于提交或非有限时间拒绝，仍保持等待", arguments: [false, true])
    func invalidReviewTimeDoesNotChangeState(nonFinite: Bool) throws {
        let setup = try makeSetup()
        let service = TaskSubmissionReviewService(context: setup.context)
        if nonFinite {
            #expect(throws: RewardLedgerError.invalidTimestamp) {
                try service.approve(
                    setup.occurrence, submissionID: setup.submissionID,
                    at: Date(timeIntervalSinceReferenceDate: .infinity))
            }
        } else {
            #expect(throws: TaskSubmissionReviewError.timeBeforeSubmission(setup.submissionID)) {
                try service.approve(
                    setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(-2))
            }
        }
        try expectWaiting(setup.context)
    }

    @Test("脏或外上下文拒绝，保留用户未提交编辑")
    func dirtyAndForeignContextsAreRejected() throws {
        let setup = try makeSetup()
        let other = ModelContext(try AppModelContainer.make(inMemory: true))
        #expect(throws: TaskCompletionServiceError.modelNotInContext) {
            try TaskSubmissionReviewService(context: other).approve(
                setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        }
        setup.occurrence.titleSnapshot = "合成未保存编辑"
        #expect(throws: RewardLedgerError.pendingContextChanges) {
            try TaskSubmissionReviewService(context: setup.context).returnForRevision(
                setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        }
        #expect(setup.context.hasChanges && setup.occurrence.titleSnapshot == "合成未保存编辑")
    }

    @Test("坏等待元数据或计时事实拒绝，审核不替原数据修补", arguments: [0, 1, 2])
    func invalidWaitingFactsCannotBeReviewed(kind: Int) throws {
        let setup = try makeSetup()
        if kind == 0 {
            let row = try #require(setup.context.fetch(FetchDescriptor<TaskSubmission>()).first)
            row.reviewedCompletionID = V0MigrationFixture.orphanID
        } else if kind == 1 {
            setup.occurrence.statusRawValue = TaskOccurrenceStatus.skipped.rawValue
        } else {
            let timer = try #require(setup.occurrence.timerSessions.first)
            timer.accumulatedActiveSeconds += 1
        }
        try setup.context.save()
        let approve = {
            try TaskSubmissionReviewService(context: setup.context).approve(
                setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        }
        if kind == 0 {
            #expect(throws: TaskSubmissionError.corruptHistory(setup.occurrence.id)) { try approve() }
        } else {
            #expect(throws: TaskSubmissionReviewError.unavailableState(setup.occurrence.id)) { try approve() }
        }
        #expect(!setup.context.hasChanges)
        try expectNoReward(setup.context)
    }

    @Test("审核保存失败同时恢复等待与原任务，不半结算", arguments: [false, true])
    func saveFailureKeepsWaiting(approve: Bool) throws {
        let setup = try makeSetup()
        setup.context.autosaveEnabled = true
        let service = TaskSubmissionReviewService(
            context: setup.context, saveChanges: { _ in throw NSError(domain: "HabitoSyntheticReviewSave", code: 1) })
        #expect(throws: NSError.self) {
            if approve {
                _ = try service.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
            } else {
                _ = try service.returnForRevision(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
            }
        }
        try expectWaiting(setup.context)
        #expect(setup.context.autosaveEnabled && !setup.context.hasChanges)
    }

    @Test("奖励加总溢出回滚审核、完成和新交易")
    func ledgerOverflowDoesNotHalfApprove() throws {
        let setup = try makeSetup()
        _ = try RewardLedgerService(context: setup.context).grantReward(
            sourceID: V0MigrationFixture.orphanID, xp: Int.max, coins: 0, at: setup.now)
        #expect(throws: RewardLedgerError.integerOverflow) {
            try TaskSubmissionReviewService(context: setup.context).approve(
                setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        }
        let row = try #require(setup.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        #expect(row.reviewState == .waiting && row.reviewedAt == nil && row.reviewedCompletionID == nil)
        #expect(
            setup.occurrence.status == .pending && setup.occurrence.completionRecord == nil && !setup.context.hasChanges
        )
        #expect(try setup.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try setup.context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
    }

    @Test("通过审计、原奖励或当前关系损坏不能幂等补发", arguments: [0, 1, 2, 3, 4])
    func corruptApprovedAuditCannotRetry(kind: Int) throws {
        let setup = try makeSetup()
        let review = TaskSubmissionReviewService(context: setup.context)
        _ = try review.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        let row = try #require(setup.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        if kind == 0 {
            row.reviewedCompletionID = V0MigrationFixture.orphanID
        } else if kind == 1 {
            row.reviewedAt = setup.now.addingTimeInterval(1)
        } else if kind == 2 {
            let xp = try #require(setup.context.fetch(FetchDescriptor<XPTransaction>()).first)
            setup.context.delete(xp)
        } else if kind == 3 {
            setup.occurrence.statusRawValue = TaskOccurrenceStatus.pending.rawValue
        } else {
            setup.occurrence.completionRecord = nil
        }
        try setup.context.save()
        let retry = {
            try review.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(2))
        }
        if kind == 0 {
            #expect(throws: TaskSubmissionError.corruptHistory(setup.occurrence.id)) { try retry() }
        } else if kind == 2 {
            #expect(throws: RewardLedgerError.self) { try retry() }
        } else {
            let id = try #require(setup.context.fetch(FetchDescriptor<CompletionRecord>()).first?.id)
            #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(id)) { try retry() }
        }
        #expect(try setup.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1 && !setup.context.hasChanges)
        #expect(try setup.context.fetchCount(FetchDescriptor<XPTransaction>()) == (kind == 2 ? 0 : 1))
    }

    @Test("已通过奖励消费后余额不足，拒绝撤销且审核事实与消费保持")
    func spentApprovalCannotBeHalfRevoked() throws {
        let setup = try makeSetup()
        let review = TaskSubmissionReviewService(context: setup.context)
        let approved = try review.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
        let completionID = try #require(approved.completionID)
        _ = try RewardLedgerService(context: setup.context).spendCoins(
            sourceID: V0MigrationFixture.orphanID, cost: 10, at: setup.now)
        #expect(throws: RewardLedgerError.insufficientCoins(required: 10, available: 0)) {
            try TaskCompletionUndoService(context: setup.context).undo(
                setup.occurrence, completionID: completionID, at: setup.now.addingTimeInterval(1))
        }
        let retry = try review.approve(
            setup.occurrence, submissionID: setup.submissionID, at: setup.now.addingTimeInterval(2))
        #expect(!retry.didReview && !retry.rewardIsRevoked && setup.occurrence.status == .completed)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 11, coins: 0))
        #expect(try setup.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 2 && !setup.context.hasChanges)
    }

    @Test("直接完成不能伪造家长通过来源")
    func directCompletionCannotForgeApproval() throws {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:30:00Z")
        let occurrence = TaskOccurrence(
            templateID: V0MigrationFixture.templateID,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: now,
            titleSnapshot: "合成自行确认", iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            sourceRevision: 1, createdAt: now, updatedAt: now)
        context.insert(occurrence)
        try context.save()
        #expect(throws: TaskCompletionServiceError.invalidConfiguration(occurrence.id)) {
            try TaskCompletionService(context: context).complete(occurrence, at: now, source: .parentApproval)
        }
        #expect(throws: TaskCompletionServiceError.invalidConfiguration(occurrence.id)) {
            try TaskProgressService(context: context).complete(occurrence, at: now, source: .parentApproval)
        }
        try expectNoReward(context)
        #expect(occurrence.status == .pending && !context.hasChanges)
    }

    @Test("磁盘成功或失败审核两次重开保持幂等与原子事实", arguments: [false, true], [false, true])
    func diskReviewPreservesAtomicFacts(approve: Bool, shouldFail: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let ids = try seedDiskReview(at: url, approve: approve, shouldFail: shouldFail)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            if shouldFail {
                try expectWaiting(context)
            } else {
                let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
                let review = TaskSubmissionReviewService(context: context)
                let now = try V0MigrationFixture.instant("2026-09-24T11:30:00Z")
                let retry =
                    try approve
                    ? review.approve(occurrence, submissionID: ids.submission, at: now)
                    : review.returnForRevision(occurrence, submissionID: ids.submission, at: now)
                #expect(!retry.didReview && retry.completionID == ids.completion)
                #expect(occurrence.status == (approve ? .completed : .pending))
                if approve {
                    let record = try #require(occurrence.completionRecord)
                    _ = try TaskCompletionAuditValidator(context: context).validate(record)
                    #expect(
                        try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 11, coins: 10)
                    )
                } else {
                    try expectNoReward(context)
                }
                #expect(occurrence.timerSessions.first?.accumulatedActiveSeconds == 30)
            }
        }
    }

    private func makeSetup(offset: TimeInterval = -1, zero: Bool = false, storeURL: URL? = nil) throws
        -> (context: ModelContext, occurrence: TaskOccurrence, now: Date, submissionID: UUID)
    {
        let container =
            try storeURL.map { try AppModelContainer.make(storeURL: $0) } ?? AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:30:00Z")
        let occurrence = TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: V0MigrationFixture.templateID,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: now,
            titleSnapshot: "合成待验收", iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            status: .inProgress, sourceRevision: 1, createdAt: now, updatedAt: now,
            verificationTypeSnapshot: .parentApproval, xpRewardSnapshot: zero ? 0 : 11,
            coinRewardSnapshot: zero ? 0 : 7, activeBonusCoinSnapshot: zero ? 0 : 3)
        let session = TimerSession(
            id: V0MigrationFixture.activeID, occurrenceID: occurrence.id, state: .paused,
            startedAt: now.addingTimeInterval(-10), lastResumedAt: now.addingTimeInterval(-10),
            accumulatedActiveSeconds: 30)
        context.insert(occurrence)
        context.insert(session)
        session.occurrence = occurrence
        try context.save()
        let submitted = try TaskSubmissionService(context: context).submit(
            occurrence, at: now.addingTimeInterval(offset))
        return (context, occurrence, now, submitted.submissionID)
    }

    private func expectNoReward(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }

    private func expectWaiting(_ context: ModelContext) throws {
        let row = try #require(context.fetch(FetchDescriptor<TaskSubmission>()).first)
        let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        #expect(row.reviewState == .waiting && row.reviewedAt == nil && row.reviewedCompletionID == nil)
        #expect(occurrence.status == .pending && occurrence.completionRecord == nil)
        #expect(
            occurrence.timerSessions.first?.state == .ended
                && occurrence.timerSessions.first?.accumulatedActiveSeconds == 30)
        try expectNoReward(context)
    }

    private func seedDiskReview(at url: URL, approve: Bool, shouldFail: Bool) throws -> (
        submission: UUID, completion: UUID?
    ) {
        let setup = try makeSetup(storeURL: url)
        let service = TaskSubmissionReviewService(
            context: setup.context,
            saveChanges: shouldFail
                ? { _ in throw NSError(domain: "HabitoSyntheticReviewSave", code: 1) } : { try $0.save() })
        var completionID: UUID?
        if shouldFail {
            #expect(throws: NSError.self) {
                if approve {
                    _ = try service.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
                } else {
                    _ = try service.returnForRevision(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
                }
            }
        } else {
            let result =
                try approve
                ? service.approve(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
                : service.returnForRevision(setup.occurrence, submissionID: setup.submissionID, at: setup.now)
            completionID = result.completionID
        }
        return (setup.submissionID, completionID)
    }
}
