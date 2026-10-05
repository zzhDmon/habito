import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("提交等待与计时原子事务")
struct TaskSubmissionServiceTests {
    @Test("提交冻结严格自主边界和奖励快照，但等待不完成不发奖", arguments: [-1.0, 0.0, 1.0])
    func submitFreezesSnapshotWithoutReward(offset: TimeInterval) throws {
        let setup = try makeSetup()
        let result = try TaskSubmissionService(context: setup.context).submit(
            setup.occurrence, at: setup.now.addingTimeInterval(offset))
        let row = try #require(setup.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        #expect(
            result.didSubmit && result.submissionID == row.id
                && result.timing == (offset < 0 ? .beforeReminder : .afterReminder))
        #expect(row.xpRewardSnapshot == 11 && row.coinRewardSnapshot == 7 && row.activeBonusCoinSnapshot == 3)
        #expect(row.reminderAtSnapshot == setup.now && row.sequenceNumber == 1 && row.reviewState == .waiting)
        #expect(row.reviewedAt == nil && row.reviewedCompletionID == nil)
        #expect(setup.occurrence.status == .pending && setup.occurrence.completionRecord == nil)
        try expectNoSettlement(setup.context)
    }

    @Test("提交结束当前运行或暂停段，累计时长不等待实际计时器", arguments: [TimerSessionState.running, .paused])
    func submissionEndsActiveTiming(state: TimerSessionState) throws {
        let setup = try makeSetup(state: state)
        let result = try TaskSubmissionService(context: setup.context).submit(setup.occurrence, at: setup.now)
        let session = try #require(setup.context.fetch(FetchDescriptor<TimerSession>()).first)
        #expect(result.activeDurationSeconds == (state == .running ? 40 : 30))
        #expect(session.state == .ended && session.endedAt == setup.now)
        #expect(session.accumulatedActiveSeconds == result.activeDurationSeconds && setup.occurrence.status == .pending)
        try expectNoSettlement(setup.context)
    }

    @Test("等待重试保持原提交，不读后来变化的提醒、奖励或验收类型")
    func waitingRetryPreservesOriginalSnapshot() throws {
        let setup = try makeSetup(state: .running)
        let service = TaskSubmissionService(context: setup.context)
        let first = try service.submit(setup.occurrence, at: setup.now.addingTimeInterval(-1))
        setup.occurrence.scheduledAt = setup.now.addingTimeInterval(-100)
        setup.occurrence.xpRewardSnapshot = 99
        setup.occurrence.coinRewardSnapshot = 88
        setup.occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.selfConfirm.rawValue
        try setup.context.save()
        let retry = try service.submit(setup.occurrence, at: setup.now.addingTimeInterval(86400))
        #expect(!retry.didSubmit && retry.submissionID == first.submissionID && retry.submittedAt == first.submittedAt)
        #expect(retry.timing == .beforeReminder && retry.activeDurationSeconds == 39)
        let row = try #require(setup.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        #expect(row.xpRewardSnapshot == 11 && row.coinRewardSnapshot == 7 && row.reminderAtSnapshot == setup.now)
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
        try expectNoSettlement(setup.context)
    }

    @Test("零奖励提交仍判自主，不以零金额当旧未知")
    func zeroRewardSubmissionStillClassifiesTiming() throws {
        let setup = try makeSetup()
        setup.occurrence.xpRewardSnapshot = 0
        setup.occurrence.coinRewardSnapshot = 0
        setup.occurrence.activeBonusCoinSnapshot = 0
        try setup.context.save()
        let result = try TaskSubmissionService(context: setup.context).submit(
            setup.occurrence, at: setup.now.addingTimeInterval(-1))
        #expect(result.timing == .beforeReminder && result.activeDurationSeconds == 0)
        try expectNoSettlement(setup.context)
    }

    @Test("明确退回后重提创建新快照和序号，原提交与累计计时保留")
    func returnedSubmissionAllowsNewSnapshotAndTiming() throws {
        let setup = try makeSetup(state: .running)
        let service = TaskSubmissionService(context: setup.context)
        let first = try service.submit(setup.occurrence, at: setup.now)
        try seedReturnedOutcome(setup.context, at: setup.now.addingTimeInterval(1))
        setup.occurrence.xpRewardSnapshot = 13
        setup.occurrence.coinRewardSnapshot = 9
        setup.occurrence.activeBonusCoinSnapshot = 4
        try setup.context.save()
        _ = try TaskProgressService(context: setup.context).startTiming(
            for: setup.occurrence, at: setup.now.addingTimeInterval(2))
        let second = try service.submit(setup.occurrence, at: setup.now.addingTimeInterval(3))
        let rows = try setup.context.fetch(FetchDescriptor<TaskSubmission>(sortBy: [SortDescriptor(\.sequenceNumber)]))
        #expect(rows.count == 2 && rows.first?.id == first.submissionID && second.submissionID != first.submissionID)
        #expect(rows.first?.reviewState == .returned && rows.first?.xpRewardSnapshot == 11)
        #expect(
            rows.last?.reviewState == .waiting && rows.last?.xpRewardSnapshot == 13
                && rows.last?.coinRewardSnapshot == 9)
        #expect(second.activeDurationSeconds == 41 && rows.map(\.sequenceNumber) == [1, 2])
        try expectNoSettlement(setup.context)
    }

    @Test("重提时间早于退回拒绝，不新建提交或改变计时")
    func timeBeforeReturnIsRejected() throws {
        let setup = try makeSetup()
        let service = TaskSubmissionService(context: setup.context)
        _ = try service.submit(setup.occurrence, at: setup.now)
        try seedReturnedOutcome(setup.context, at: setup.now.addingTimeInterval(10))
        #expect(throws: TaskSubmissionError.timeBeforePreviousReview(setup.occurrence.id)) {
            try service.submit(setup.occurrence, at: setup.now.addingTimeInterval(9))
        }
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1 && !setup.context.hasChanges)
    }

    @Test("自行确认实例拒绝家长验收提交")
    func selfConfirmCannotSubmitForApproval() throws {
        let setup = try makeSetup()
        setup.occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.selfConfirm.rawValue
        try setup.context.save()
        #expect(throws: TaskSubmissionError.parentApprovalRequired(setup.occurrence.id)) {
            try TaskSubmissionService(context: setup.context).submit(setup.occurrence, at: setup.now)
        }
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
    }

    @Test("已处理或跳过状态不允许提交", arguments: [TaskOccurrenceStatus.completed, .skipped])
    func processedStatusesCannotSubmit(status: TaskOccurrenceStatus) throws {
        let setup = try makeSetup()
        setup.occurrence.statusRawValue = status.rawValue
        try setup.context.save()
        #expect(throws: TaskSubmissionError.unavailableState(setup.occurrence.id)) {
            try TaskSubmissionService(context: setup.context).submit(setup.occurrence, at: setup.now)
        }
        #expect(setup.occurrence.status == status && !setup.context.hasChanges)
    }

    @Test("等待不能从计时、旧完成、新完成或家长更正入口绕过")
    func waitingGuardsAllTimingAndCompletionWrites() throws {
        let setup = try makeSetup()
        _ = try TaskSubmissionService(context: setup.context).submit(setup.occurrence, at: setup.now)
        let progress = TaskProgressService(context: setup.context)
        let failure = TaskSubmissionError.awaitingReview(setup.occurrence.id)
        #expect(throws: failure) { try progress.startTiming(for: setup.occurrence, at: setup.now) }
        #expect(throws: failure) { try progress.pauseTiming(for: setup.occurrence, at: setup.now) }
        #expect(throws: failure) { try progress.resumeTiming(for: setup.occurrence, at: setup.now) }
        #expect(throws: failure) { try progress.endTiming(for: setup.occurrence, at: setup.now) }
        #expect(throws: failure) { try progress.complete(setup.occurrence, at: setup.now, source: .childManual) }
        #expect(throws: failure) {
            try TaskCompletionService(context: setup.context).complete(
                setup.occurrence, at: setup.now, source: .childManual)
        }
        #expect(throws: failure) {
            try TaskCompletionService(context: setup.context).correctAsCompleted(setup.occurrence, at: setup.now)
        }
        #expect(!setup.context.hasChanges)
        try expectNoSettlement(setup.context)
    }

    @Test("等待稍后请求在系统操作前拒绝，不遗留通知映射")
    func waitingCannotScheduleSnooze() async throws {
        let setup = try makeSetup()
        _ = try TaskSubmissionService(context: setup.context).submit(setup.occurrence, at: setup.now)
        let provider = UITestNotificationPermissionProvider(deniesAuthorization: false)
        let service = TaskSnoozeService(
            context: setup.context, scheduler: provider, permissionProvider: provider,
            calendar: Calendar(identifier: .gregorian), timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")))
        await #expect(throws: TaskSubmissionError.awaitingReview(setup.occurrence.id)) {
            try await service.schedule(occurrenceID: setup.occurrence.id, at: setup.now)
        }
        #expect(try await provider.pendingNotificationRequests().isEmpty)
        #expect(try setup.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("脏或外上下文拒绝且保留用户编辑")
    func dirtyAndForeignContextsPreserveEdits() throws {
        let setup = try makeSetup()
        let other = ModelContext(setup.context.container)
        #expect(throws: TaskCompletionServiceError.modelNotInContext) {
            try TaskSubmissionService(context: other).submit(setup.occurrence, at: setup.now)
        }
        setup.occurrence.titleSnapshot = "合成未保存编辑"
        #expect(throws: RewardLedgerError.pendingContextChanges) {
            try TaskSubmissionService(context: setup.context).submit(setup.occurrence, at: setup.now)
        }
        #expect(setup.context.hasChanges && setup.occurrence.titleSnapshot == "合成未保存编辑")
    }

    @Test("非法奖励、非有限时间和累计时长拒绝，不半结束计时")
    func invalidInputsCannotCreateSubmission() throws {
        let setup = try makeSetup(state: .paused)
        let service = TaskSubmissionService(context: setup.context)
        #expect(throws: RewardLedgerError.invalidTimestamp) {
            try service.submit(setup.occurrence, at: Date(timeIntervalSinceReferenceDate: .infinity))
        }
        setup.occurrence.xpRewardSnapshot = -1
        try setup.context.save()
        #expect(throws: RewardLedgerError.invalidAmount) { try service.submit(setup.occurrence, at: setup.now) }
        setup.occurrence.xpRewardSnapshot = 11
        let session = try #require(setup.context.fetch(FetchDescriptor<TimerSession>()).first)
        session.accumulatedActiveSeconds = .infinity
        try setup.context.save()
        #expect(throws: TaskCompletionServiceError.invalidDuration(setup.occurrence.id)) {
            try service.submit(setup.occurrence, at: setup.now)
        }
        #expect(session.state == .paused && session.endedAt == nil && !setup.context.hasChanges)
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
    }

    @Test("运行段时间倒退拒绝，原状态和时长不变")
    func backwardsRunningTimeIsRejected() throws {
        let setup = try makeSetup(state: .running)
        #expect(throws: TaskProgressServiceError.timeBeforeLastResume(sessionID: V0MigrationFixture.activeID)) {
            try TaskSubmissionService(context: setup.context).submit(
                setup.occurrence, at: setup.now.addingTimeInterval(-20))
        }
        let session = try #require(setup.context.fetch(FetchDescriptor<TimerSession>()).first)
        #expect(session.state == .running && session.accumulatedActiveSeconds == 30 && session.endedAt == nil)
        #expect(setup.occurrence.status == .inProgress && !setup.context.hasChanges)
    }

    @Test("损坏等待元数据拒绝，不当作幂等成功")
    func corruptWaitingMetadataIsRejected() throws {
        let setup = try makeSetup()
        let service = TaskSubmissionService(context: setup.context)
        _ = try service.submit(setup.occurrence, at: setup.now)
        let row = try #require(setup.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        row.reviewedAt = setup.now
        try setup.context.save()
        #expect(throws: TaskSubmissionError.corruptHistory(setup.occurrence.id)) {
            try service.submit(setup.occurrence, at: setup.now)
        }
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
    }

    @Test("保存失败恢复运行或暂停与原任务状态，不留下提交", arguments: [TimerSessionState.running, .paused])
    func saveFailureRestoresTiming(state: TimerSessionState) throws {
        let setup = try makeSetup(state: state)
        setup.context.autosaveEnabled = true
        let service = TaskSubmissionService(
            context: setup.context, saveChanges: { _ in throw NSError(domain: "HabitoSyntheticSave", code: 1) })
        #expect(throws: NSError.self) { try service.submit(setup.occurrence, at: setup.now) }
        try expectOriginalTiming(setup.context, state: state)
        #expect(setup.context.autosaveEnabled && !setup.context.hasChanges)
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
        try expectNoSettlement(setup.context)
    }

    @Test("磁盘重开保持提交幂等或失败前的原运行事实", arguments: [false, true])
    func diskSubmissionKeepsAtomicFacts(shouldFail: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let savedID = try seedDiskSubmission(at: url, shouldFail: shouldFail)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            if shouldFail {
                try expectOriginalTiming(context, state: .running)
                #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
            } else {
                let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
                let retry = try TaskSubmissionService(context: context).submit(
                    occurrence, at: V0MigrationFixture.instant("2026-09-23T11:30:00Z"))
                #expect(!retry.didSubmit && retry.submissionID == savedID && retry.activeDurationSeconds == 40)
                #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1 && occurrence.status == .pending)
            }
            try expectNoSettlement(context)
        }
    }

    @Test("损坏计时终态或暂停后时间倒退拒绝，提交不修补原事实", arguments: [0, 1, 2, 3])
    func invalidSessionTimelineCannotBeSubmitted(kind: Int) throws {
        let setup = try makeSetup(state: .paused)
        let session = try #require(setup.context.fetch(FetchDescriptor<TimerSession>()).first)
        if kind == 0 {
            session.stateRawValue = TimerSessionState.running.rawValue
            session.endedAt = setup.now
        } else if kind == 1 {
            session.stateRawValue = TimerSessionState.ended.rawValue
        } else if kind == 2 {
            session.lastResumedAt = setup.now.addingTimeInterval(1)
        } else {
            session.stateRawValue = TimerSessionState.ended.rawValue
            session.endedAt = setup.now.addingTimeInterval(1)
        }
        try setup.context.save()
        let service = TaskSubmissionService(context: setup.context)
        if kind == 2 {
            #expect(throws: TaskProgressServiceError.timeBeforeLastResume(sessionID: session.id)) {
                try service.submit(setup.occurrence, at: setup.now)
            }
        } else {
            #expect(
                throws: TaskProgressServiceError.inconsistentOccurrenceAndSessionState(
                    occurrenceID: setup.occurrence.id)
            ) {
                try service.submit(setup.occurrence, at: setup.now)
            }
        }
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0 && !setup.context.hasChanges)
        #expect(setup.occurrence.status == .inProgress && session.accumulatedActiveSeconds == 30)
        try expectNoSettlement(setup.context)
    }

    @Test("等待重试遇到已损坏的结束段拒绝，不只按相等秒数返回成功")
    func waitingRetryValidatesEndedTimeline() throws {
        let setup = try makeSetup(state: .running)
        let service = TaskSubmissionService(context: setup.context)
        _ = try service.submit(setup.occurrence, at: setup.now)
        let session = try #require(setup.context.fetch(FetchDescriptor<TimerSession>()).first)
        session.endedAt = nil
        try setup.context.save()
        #expect(
            throws: TaskProgressServiceError.inconsistentOccurrenceAndSessionState(occurrenceID: setup.occurrence.id)
        ) {
            try service.submit(setup.occurrence, at: setup.now)
        }
        #expect(try setup.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1 && session.endedAt == nil)
    }

    private func makeSetup(state: TimerSessionState? = nil, storeURL: URL? = nil) throws
        -> (context: ModelContext, occurrence: TaskOccurrence, now: Date)
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
            status: state == nil ? .pending : .inProgress, sourceRevision: 1, createdAt: now, updatedAt: now,
            verificationTypeSnapshot: .parentApproval, xpRewardSnapshot: 11, coinRewardSnapshot: 7,
            activeBonusCoinSnapshot: 3)
        context.insert(occurrence)
        if let state {
            let session = TimerSession(
                id: V0MigrationFixture.activeID, occurrenceID: occurrence.id, state: state,
                startedAt: now.addingTimeInterval(-10), lastResumedAt: now.addingTimeInterval(-10),
                accumulatedActiveSeconds: 30)
            context.insert(session)
            session.occurrence = occurrence
        }
        try context.save()
        return (context, occurrence, now)
    }

    private func expectNoSettlement(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }

    private func expectOriginalTiming(_ context: ModelContext, state: TimerSessionState) throws {
        let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        let session = try #require(context.fetch(FetchDescriptor<TimerSession>()).first)
        #expect(occurrence.status == .inProgress && session.state == state)
        #expect(session.accumulatedActiveSeconds == 30 && session.endedAt == nil)
    }

    /// 仅为提交卡提供已退回输入，不冒充下一卡审核事务的验收证据。
    private func seedReturnedOutcome(_ context: ModelContext, at reviewedAt: Date) throws {
        let row = try #require(context.fetch(FetchDescriptor<TaskSubmission>()).first)
        row.reviewStateRawValue = SubmissionReviewState.returned.rawValue
        row.reviewedAt = reviewedAt
        try context.save()
    }

    private func seedDiskSubmission(at url: URL, shouldFail: Bool) throws -> UUID? {
        let setup = try makeSetup(state: .running, storeURL: url)
        let service = TaskSubmissionService(
            context: setup.context,
            saveChanges: shouldFail ? { _ in throw NSError(domain: "HabitoSyntheticSave", code: 1) } : { try $0.save() }
        )
        if shouldFail {
            #expect(throws: NSError.self) { try service.submit(setup.occurrence, at: setup.now) }
            return nil
        }
        return try service.submit(setup.occurrence, at: setup.now).submissionID
    }
}
