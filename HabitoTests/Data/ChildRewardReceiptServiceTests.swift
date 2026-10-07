import Foundation
import SwiftData
import Testing
@testable import Habito

/// 收据只使用固定时刻与合成审核，不让真实当前时间、家庭数据库或通知参与测试。
@MainActor
struct ChildRewardReceiptServiceTests {
    @Test("普通/自主/零奖励次日通过查询是真实快照且不写库", arguments: [-1.0, 0.0, 1.0], [false, true])
    func approvedReceiptPreservesFacts(offset: TimeInterval, zero: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting(submittedOffset: 60 + offset, zero: zero)
        let settledAt = fixture.now.addingTimeInterval(86_400)
        let record = try approve(occurrence, fixture: fixture, at: settledAt)
        let service = ChildRewardReceiptService(context: fixture.context)
        let receipt = try #require(service.pendingReceipts().first)
        #expect(receipt.completionID == record.id && receipt.occurrenceID == occurrence.id)
        #expect(receipt.title == occurrence.titleSnapshot && receipt.completedAt == record.completedAt)
        #expect(receipt.settledAt == settledAt && receipt.timing == (offset < 0 ? .beforeReminder : .afterReminder))
        #expect(receipt.xp == (zero ? 0 : 11) && receipt.coins == (zero ? 0 : (offset < 0 ? 10 : 7)))
        #expect(record.childFeedbackDeliveryVersion == 1 && record.childFeedbackAcknowledgedAt == nil)
        #expect(try service.pendingReceipts() == [receipt])
        try expectTransactions(fixture.context, count: 1)
        #expect(!fixture.context.hasChanges)
    }

    @Test("等待与退回无收据，新通过才有收据，撤销后陈旧确认不可用")
    func waitingReturnedAndRevokedDoNotDeliver() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        let service = ChildRewardReceiptService(context: fixture.context)
        #expect(try service.pendingReceipts().isEmpty)
        _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
            occurrence, submissionID: row.id, at: fixture.now)
        #expect(try service.pendingReceipts().isEmpty)
        _ = try TaskProgressService(context: fixture.context).startTiming(
            for: occurrence, at: fixture.now.addingTimeInterval(1))
        _ = try TaskSubmissionService(context: fixture.context).submit(
            occurrence, at: fixture.now.addingTimeInterval(2))
        let record = try approve(occurrence, fixture: fixture, at: fixture.now.addingTimeInterval(3))
        #expect(try service.pendingReceipts().count == 1)
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: record.id, at: fixture.now.addingTimeInterval(4))
        #expect(try service.pendingReceipts().isEmpty)
        #expect(throws: ChildRewardReceiptError.unavailableReceipt(record.id)) {
            try service.acknowledge(completionID: record.id, at: fixture.now.addingTimeInterval(5))
        }
        #expect(record.childFeedbackAcknowledgedAt == nil)
        try expectTransactions(fixture.context, count: 2)
    }

    @Test("稳定ID确认幂等，不修改完成或账本，重复通过不清除已读")
    func acknowledgementAndApprovalRetryAreIdempotent() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let record = try approve(occurrence, fixture: fixture)
        let originalUpdatedAt = record.updatedAt
        let service = ChildRewardReceiptService(context: fixture.context)
        let acknowledgedAt = fixture.now.addingTimeInterval(10)
        #expect(try service.acknowledge(completionID: record.id, at: acknowledgedAt))
        let retry = ChildRewardReceiptService(
            context: fixture.context,
            saveChanges: { _ in
                Issue.record("重复确认不能保存")
            })
        #expect(try !retry.acknowledge(completionID: record.id, at: acknowledgedAt.addingTimeInterval(1)))
        #expect(record.childFeedbackAcknowledgedAt == acknowledgedAt && record.updatedAt == originalUpdatedAt)
        #expect(try service.pendingReceipts().isEmpty)
        let submissionID = try #require(record.submissionID)
        let result = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: submissionID, at: acknowledgedAt.addingTimeInterval(2))
        #expect(!result.didReview && result.completionID == record.id)
        #expect(record.childFeedbackAcknowledgedAt == acknowledgedAt)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("确认失败恢复未读及自动保存，重试只确认不发奖", arguments: [false, true])
    func failedAcknowledgementPreservesPending(autosave: Bool) throws {
        let fixture = try ParentReviewFixture()
        let record = try approve(fixture.makeWaiting(), fixture: fixture)
        fixture.context.autosaveEnabled = autosave
        let service = ChildRewardReceiptService(
            context: fixture.context,
            saveChanges: { _ in
                throw NSError(domain: "HabitoSyntheticReceiptSave", code: 1)
            })
        #expect(throws: NSError.self) {
            try service.acknowledge(completionID: record.id, at: fixture.now.addingTimeInterval(1))
        }
        #expect(record.childFeedbackAcknowledgedAt == nil && !fixture.context.hasChanges)
        #expect(fixture.context.autosaveEnabled == autosave)
        let normal = ChildRewardReceiptService(context: fixture.context)
        #expect(try normal.pendingReceipts().map(\.completionID) == [record.id])
        #expect(try normal.acknowledge(completionID: record.id, at: fixture.now.addingTimeInterval(2)))
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("脏编辑拒绝查询与确认，不保存或回滚调用方数据")
    func dirtyContextIsPreserved() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let record = try approve(occurrence, fixture: fixture)
        occurrence.titleSnapshot = "尚未保存的用户编辑"
        let service = ChildRewardReceiptService(context: fixture.context)
        #expect(throws: RewardLedgerError.pendingContextChanges) { try service.pendingReceipts() }
        #expect(throws: RewardLedgerError.pendingContextChanges) {
            try service.acknowledge(completionID: record.id, at: fixture.now)
        }
        #expect(fixture.context.hasChanges && occurrence.titleSnapshot == "尚未保存的用户编辑")
        #expect(record.childFeedbackAcknowledgedAt == nil)
    }

    @Test("确认拒绝不存在、到账前与非有限时间", arguments: [0, 1, 2, 3])
    func invalidAcknowledgementIsRejected(kind: Int) throws {
        let fixture = try ParentReviewFixture()
        let record = try approve(fixture.makeWaiting(), fixture: fixture)
        let service = ChildRewardReceiptService(context: fixture.context)
        if kind == 0 {
            #expect(throws: ChildRewardReceiptError.completionNotFound(V0MigrationFixture.orphanID)) {
                try service.acknowledge(completionID: V0MigrationFixture.orphanID, at: fixture.now)
            }
        } else if kind == 1 {
            #expect(throws: ChildRewardReceiptError.acknowledgementBeforeSettlement(record.id)) {
                try service.acknowledge(completionID: record.id, at: fixture.now.addingTimeInterval(-1))
            }
        } else {
            #expect(throws: RewardLedgerError.invalidTimestamp) {
                try service.acknowledge(
                    completionID: record.id, at: Date(timeIntervalSinceReferenceDate: kind == 2 ? .infinity : .nan))
            }
        }
        #expect(record.childFeedbackAcknowledgedAt == nil && !fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("坏审核、账本或投递确认时刻不伪装成到账", arguments: [0, 1, 2, 3])
    func corruptFactsCannotDeliver(kind: Int) throws {
        let fixture = try ParentReviewFixture()
        let record = try approve(fixture.makeWaiting(), fixture: fixture)
        if kind == 0 {
            let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
            row.reviewedCompletionID = V0MigrationFixture.orphanID
        } else if kind == 1 {
            let coin = try #require(fixture.context.fetch(FetchDescriptor<CoinTransaction>()).first)
            fixture.context.delete(coin)
        } else {
            record.childFeedbackAcknowledgedAt =
                kind == 2
                ? fixture.now.addingTimeInterval(-1) : Date(timeIntervalSinceReferenceDate: .infinity)
        }
        try fixture.context.save()
        let service = ChildRewardReceiptService(context: fixture.context)
        if kind == 0 {
            #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(record.id)) {
                try service.pendingReceipts()
            }
            #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(record.id)) {
                try service.acknowledge(completionID: record.id, at: fixture.now.addingTimeInterval(2))
            }
        } else if kind == 1 {
            #expect(throws: RewardLedgerError.self) { try service.pendingReceipts() }
            #expect(throws: RewardLedgerError.self) {
                try service.acknowledge(completionID: record.id, at: fixture.now.addingTimeInterval(2))
            }
        } else {
            #expect(throws: ChildRewardReceiptError.invalidDeliveryMetadata(record.id)) {
                try service.pendingReceipts()
            }
            #expect(throws: ChildRewardReceiptError.invalidDeliveryMetadata(record.id)) {
                try service.acknowledge(completionID: record.id, at: fixture.now.addingTimeInterval(2))
            }
        }
        #expect(!fixture.context.hasChanges)
    }

    @Test("多日收据按真实结算排序，同刻用稳定ID，确认一条不吞其余")
    func multipleCrossDayReceiptsAreStable() throws {
        let fixture = try ParentReviewFixture()
        let first = try fixture.makeWaiting(day: "2026-09-20")
        let second = try fixture.makeWaiting(id: V0MigrationFixture.completedID, day: "2026-09-21")
        let third = try fixture.makeWaiting(id: V0MigrationFixture.orphanID)
        let late = try approve(first, fixture: fixture, at: fixture.now.addingTimeInterval(20))
        let early = try approve(second, fixture: fixture, at: fixture.now.addingTimeInterval(10))
        let same = try approve(third, fixture: fixture, at: fixture.now.addingTimeInterval(10))
        let service = ChildRewardReceiptService(context: fixture.context)
        let tie = [early.id, same.id].sorted { $0.uuidString < $1.uuidString }
        #expect(try service.pendingReceipts().map(\.completionID) == tie + [late.id])
        _ = try service.acknowledge(completionID: early.id, at: fixture.now.addingTimeInterval(30))
        #expect(try service.pendingReceipts().map(\.completionID) == [same.id, late.id])
        try expectTransactions(fixture.context, count: 3)
    }

    @Test("磁盘退出未确认可重见，确认后多次重开不再投递", arguments: [false, true])
    func diskReopenPreservesLifecycle(zero: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let completionID = try seedPending(at: url, zero: zero)
        try reopenPendingAndAcknowledge(at: url, id: completionID)
        for _ in 0..<2 {
            let fixture = try ParentReviewFixture(storeURL: url)
            #expect(try ChildRewardReceiptService(context: fixture.context).pendingReceipts().isEmpty)
            let record = try #require(fixture.context.fetch(FetchDescriptor<CompletionRecord>()).first)
            #expect(
                record.id == completionID && record.childFeedbackAcknowledgedAt == fixture.now.addingTimeInterval(2))
            _ = try TaskCompletionAuditValidator(context: fixture.context).validate(record)
            try expectTransactions(fixture.context, count: 1)
        }
    }

    @Test("磁盘确认失败两次重开仍待确认，交易与审计不变")
    func failedDiskAcknowledgementRemainsPending() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let id = try seedPending(at: url, zero: false)
        try failDiskAcknowledgement(at: url, id: id)
        for _ in 0..<2 {
            let fixture = try ParentReviewFixture(storeURL: url)
            #expect(
                try ChildRewardReceiptService(context: fixture.context).pendingReceipts().map(\.completionID) == [id])
            let record = try #require(fixture.context.fetch(FetchDescriptor<CompletionRecord>()).first)
            #expect(record.childFeedbackAcknowledgedAt == nil)
            _ = try TaskCompletionAuditValidator(context: fixture.context).validate(record)
            try expectTransactions(fixture.context, count: 1)
        }
    }

    @Test("旧六版审核历史不补弹，重复通过也不补标")
    func migratedHistoryNeverBecomesPending() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V5MigrationFixture.seed(at: url)
        let fixture = try ParentReviewFixture(storeURL: url)
        let service = ChildRewardReceiptService(context: fixture.context)
        #expect(try service.pendingReceipts().isEmpty)
        let records = try fixture.context.fetch(FetchDescriptor<CompletionRecord>())
        let approved = try #require(records.first { $0.completionSource == .parentApproval && $0.revokedAt == nil })
        let occurrence = try #require(approved.occurrence)
        let submissionID = try #require(approved.submissionID)
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: submissionID, at: fixture.now.addingTimeInterval(86_400))
        #expect(approved.childFeedbackDeliveryVersion == 0 && approved.childFeedbackAcknowledgedAt == nil)
        #expect(try service.pendingReceipts().isEmpty)
        #expect(throws: ChildRewardReceiptError.unavailableReceipt(approved.id)) {
            try service.acknowledge(completionID: approved.id, at: fixture.now.addingTimeInterval(86_400))
        }
        #expect(!fixture.context.hasChanges)
    }

    @Test("未知版本、来源或旧版带已读元数据明确拒绝", arguments: [-1, 2, 0, 1])
    func invalidDeliveryMetadataIsRejected(version: Int) throws {
        let fixture = try ParentReviewFixture()
        let record = CompletionRecord(
            occurrenceID: V0MigrationFixture.orphanID, completedAt: fixture.now,
            activeDurationSeconds: 0, completionSource: .childManual,
            createdAt: fixture.now, updatedAt: fixture.now,
            childFeedbackDeliveryVersion: version,
            childFeedbackAcknowledgedAt: version == 0 ? fixture.now : nil)
        fixture.context.insert(record)
        try fixture.context.save()
        let service = ChildRewardReceiptService(context: fixture.context)
        #expect(throws: ChildRewardReceiptError.invalidDeliveryMetadata(record.id)) { try service.pendingReceipts() }
        #expect(throws: ChildRewardReceiptError.invalidDeliveryMetadata(record.id)) {
            try service.acknowledge(completionID: record.id, at: fixture.now)
        }
        #expect(!fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 0)
    }

    @Test("自行确认已有即时反馈，不加入审核未读队列")
    func selfConfirmationDoesNotDoubleDeliver() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = TaskOccurrence(
            templateID: V0MigrationFixture.templateID, date: try LocalDate(dateKey: "2026-09-23"),
            scheduledAt: fixture.now.addingTimeInterval(60), titleSnapshot: "合成自行确认",
            iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            sourceRevision: 1, createdAt: fixture.now, updatedAt: fixture.now,
            verificationTypeSnapshot: .selfConfirm, xpRewardSnapshot: 11, coinRewardSnapshot: 7,
            activeBonusCoinSnapshot: 3)
        fixture.context.insert(occurrence)
        try fixture.context.save()
        _ = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        let record = try #require(occurrence.completionRecord)
        #expect(record.childFeedbackDeliveryVersion == 0 && record.childFeedbackAcknowledgedAt == nil)
        #expect(try ChildRewardReceiptService(context: fixture.context).pendingReceipts().isEmpty)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("通过保存失败无投递事实，成功重试与重复通过只有同一未读收据")
    func failedApprovalCannotCreateFeedback() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        let failing = TaskSubmissionReviewService(
            context: fixture.context,
            saveChanges: { _ in
                throw NSError(domain: "HabitoSyntheticApprovalReceiptSave", code: 1)
            })
        #expect(throws: NSError.self) {
            try failing.approve(occurrence, submissionID: row.id, at: fixture.now)
        }
        let service = ChildRewardReceiptService(context: fixture.context)
        #expect(try service.pendingReceipts().isEmpty && !fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 0)
        let record = try approve(occurrence, fixture: fixture)
        let original = try service.pendingReceipts()
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: row.id, at: fixture.now.addingTimeInterval(1))
        #expect(try service.pendingReceipts() == original && original.map(\.completionID) == [record.id])
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("隔离进程探针坏参数拒绝，无参数不访问或回滚脏上下文", arguments: [0, 1, 2])
    func processProbeRequiresExplicitIsolatedArguments(kind: Int) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        occurrence.titleSnapshot = "未保存的探针隔离验证"
        try UITestRewardReceiptProbe.prepare(context: fixture.context, arguments: [])
        let probe = UITestRewardReceiptProbe.argument
        let enabled = UITestLaunchConfiguration.enableArgument
        let arguments = kind == 0 ? [probe, "pending"] : kind == 1 ? [enabled, probe] : [enabled, probe, "invalid"]
        #expect(throws: CocoaError.self) {
            try UITestRewardReceiptProbe.prepare(context: fixture.context, arguments: arguments)
        }
        #expect(throws: RewardLedgerError.pendingContextChanges) {
            try UITestRewardReceiptProbe.prepare(context: fixture.context, arguments: [enabled, probe, "pending"])
        }
        #expect(fixture.context.hasChanges && occurrence.titleSnapshot == "未保存的探针隔离验证")
    }

    private func approve(_ occurrence: TaskOccurrence, fixture: ParentReviewFixture, at date: Date? = nil) throws
        -> CompletionRecord
    {
        let row = try #require(
            fixture.context.fetch(FetchDescriptor<TaskSubmission>()).last {
                $0.occurrenceID == occurrence.id && $0.reviewState == .waiting
            })
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: row.id, at: date ?? fixture.now)
        return try #require(occurrence.completionRecord)
    }

    private func expectTransactions(_ context: ModelContext, count: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == count)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == count)
    }

    private func seedPending(at url: URL, zero: Bool) throws -> UUID {
        let fixture = try ParentReviewFixture(storeURL: url)
        return try approve(fixture.makeWaiting(zero: zero), fixture: fixture).id
    }

    private func reopenPendingAndAcknowledge(at url: URL, id: UUID) throws {
        let fixture = try ParentReviewFixture(storeURL: url)
        let service = ChildRewardReceiptService(context: fixture.context)
        #expect(try service.pendingReceipts().map(\.completionID) == [id])
        #expect(try service.pendingReceipts().map(\.completionID) == [id])
        try expectTransactions(fixture.context, count: 1)
        _ = try service.acknowledge(completionID: id, at: fixture.now.addingTimeInterval(2))
    }

    private func failDiskAcknowledgement(at url: URL, id: UUID) throws {
        let fixture = try ParentReviewFixture(storeURL: url)
        let service = ChildRewardReceiptService(
            context: fixture.context,
            saveChanges: { _ in
                throw NSError(domain: "HabitoSyntheticDiskReceiptSave", code: 1)
            })
        #expect(throws: NSError.self) {
            try service.acknowledge(completionID: id, at: fixture.now.addingTimeInterval(1))
        }
        #expect(!fixture.context.hasChanges)
    }
}
