import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("自行确认原子结算")
struct TaskCompletionServiceTests {
    @Test("提醒前相等后严格判定，基础奖励不因晚于提醒或截止减少", arguments: [-1.0, 0.0, 1.0])
    func strictBoundaryFreezesActualReward(offset: TimeInterval) throws {
        let setup = try makeSetup()
        setup.occurrence.deadlineAt = setup.now.addingTimeInterval(-60)
        try setup.context.save()
        let result = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence, at: setup.now.addingTimeInterval(offset), source: .childManual)
        let record = try #require(setup.occurrence.completionRecord)
        #expect(result.didComplete && result.completionID == record.id)
        #expect(result.timing == (offset < 0 ? .beforeReminder : .afterReminder))
        #expect(result.xp == 11 && result.coins == (offset < 0 ? 10 : 7))
        #expect(record.reminderAtSnapshot == setup.now && record.rewardSettlementVersion == 1)
        #expect(record.xpRewardSnapshot == 11 && record.coinRewardSnapshot == 7 && record.activeBonusCoinSnapshot == 3)
        #expect(record.settledCoinSnapshot == result.coins && record.completionTiming == result.timing)
        #expect(
            try RewardLedgerService(context: setup.context).balance()
                == RewardBalance(effectiveXP: 11, coins: result.coins))
        try expectCounts(setup.context, completions: 1, xp: 1, coin: 1)
    }

    @Test("重复完成使用原快照，新配置或重试时刻不能重算奖励")
    func retryReturnsOriginalReceiptDespiteConfigurationChanges() throws {
        let setup = try makeSetup()
        let service = TaskCompletionService(context: setup.context)
        let first = try service.complete(setup.occurrence, at: setup.now.addingTimeInterval(-1), source: .childManual)
        setup.occurrence.scheduledAt = setup.now.addingTimeInterval(-1000)
        setup.occurrence.xpRewardSnapshot = 99
        setup.occurrence.coinRewardSnapshot = 88
        setup.occurrence.activeBonusCoinSnapshot = 77
        setup.occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try setup.context.save()
        let retry = try service.complete(
            setup.occurrence, at: setup.now.addingTimeInterval(100), source: .parentCorrection)
        #expect(!retry.didComplete && retry.completionID == first.completionID)
        #expect(retry.completedAt == first.completedAt && retry.timing == .beforeReminder)
        #expect(retry.xp == 11 && retry.coins == 10)
        try expectCounts(setup.context, completions: 1, xp: 1, coin: 1)
    }

    @Test("零奖励旧任务新提交仍正常判定自主，零交易确保幂等")
    func zeroRewardNewSubmissionIsNotUnknown() throws {
        let setup = try makeSetup(xp: 0, coins: 0, bonus: 0)
        let result = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence, at: setup.now.addingTimeInterval(-1), source: .childManual)
        #expect(result.timing == .beforeReminder && result.xp == 0 && result.coins == 0)
        #expect(setup.occurrence.completionRecord?.rewardSettlementVersion == 1)
        try expectCounts(setup.context, completions: 1, xp: 1, coin: 1)
    }

    @Test("已有旧完成只返回历史，不补奖或改写自主性")
    func legacyCompletedRecordIsNeverBackfilled() throws {
        let setup = try makeSetup()
        let old = try TaskProgressService(context: setup.context).complete(
            setup.occurrence, at: setup.now, source: .childManual)
        let result = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence, at: setup.now.addingTimeInterval(10), source: .childManual)
        #expect(!result.didComplete && result.completionID == old.id && result.timing == .unknown)
        #expect(result.xp == 0 && result.coins == 0 && old.rewardSettlementVersion == 0)
        #expect(old.reminderAtSnapshot == nil)
        try expectCounts(setup.context, completions: 1, xp: 0, coin: 0)
    }

    @Test("旧删除撤销入口拒绝新结算，不允许删除已经发奖的完成事实")
    func legacyUndoCannotDeleteSettledFact() throws {
        let setup = try makeSetup()
        let result = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence, at: setup.now, source: .childManual)
        #expect(throws: TaskCompletionServiceError.legacyUndoCannotDeleteSettlement(result.completionID)) {
            try TaskProgressService(context: setup.context).undoCompletion(of: setup.occurrence, at: setup.now)
        }
        #expect(setup.occurrence.status == .completed && setup.occurrence.completionRecord?.id == result.completionID)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 11, coins: 7))
        try expectCounts(setup.context, completions: 1, xp: 1, coin: 1)
        #expect(!setup.context.hasChanges)
    }

    @Test("计时终态与完成奖励共同保存，历次活动时间累计保持")
    func timingAndRewardCommitTogether() throws {
        let setup = try makeSetup(running: true)
        let result = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence, at: setup.now.addingTimeInterval(-1), source: .childManual)
        let record = try #require(setup.occurrence.completionRecord)
        #expect(record.activeDurationSeconds == 349 && setup.occurrence.status == .completed)
        let running = try #require(
            setup.context.fetch(FetchDescriptor<TimerSession>()).first { $0.id == V0MigrationFixture.activeID })
        #expect(running.state == .ended && running.accumulatedActiveSeconds == 149)
        #expect(running.endedAt == result.completedAt)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
    }

    @Test("保存失败回滚计时完成和两笔奖励，不留下半成功")
    func saveFailureRestoresEntireCompletion() throws {
        let setup = try makeSetup(running: true)
        let service = TaskCompletionService(
            context: setup.context, saveChanges: { _ in throw RewardLedgerError.invalidTimestamp })
        #expect(throws: RewardLedgerError.invalidTimestamp) {
            try service.complete(setup.occurrence, at: setup.now, source: .childManual)
        }
        try expectUnchangedRunningSetup(setup.context)
    }

    @Test("账本溢出在暂存完成后拒绝，任务和计时也回滚")
    func ledgerOverflowRollsBackStagedTaskFacts() throws {
        let setup = try makeSetup(running: true)
        _ = try RewardLedgerService(context: setup.context).grantReward(
            sourceID: V0MigrationFixture.orphanID,
            xp: Int.max, coins: 0, at: setup.now)
        #expect(throws: RewardLedgerError.integerOverflow) {
            try TaskCompletionService(context: setup.context).complete(
                setup.occurrence, at: setup.now, source: .childManual)
        }
        #expect(setup.occurrence.status == .inProgress && setup.occurrence.completionRecord == nil)
        let running = try #require(
            setup.context.fetch(FetchDescriptor<TimerSession>()).first { $0.id == V0MigrationFixture.activeID })
        #expect(running.state == .running && running.accumulatedActiveSeconds == 100 && running.endedAt == nil)
        try expectCounts(setup.context, completions: 0, xp: 1, coin: 1)
        #expect(!setup.context.hasChanges)
    }

    @Test("自主加总溢出或负奖励拒绝，尚未结束计时", arguments: [true, false])
    func invalidConfiguredRewardDoesNotMutateTask(overflow: Bool) throws {
        let setup = try makeSetup(coins: overflow ? Int.max : -1, bonus: 1, running: true)
        #expect(throws: overflow ? RewardLedgerError.integerOverflow : RewardLedgerError.invalidAmount) {
            try TaskCompletionService(context: setup.context).complete(
                setup.occurrence, at: setup.now.addingTimeInterval(-1), source: .childManual)
        }
        try expectUnchangedRunningSetup(setup.context)
    }

    @Test("家长验收任务不能绕过等待直接结算")
    func parentApprovalCannotUseSelfConfirmation() throws {
        let setup = try makeSetup(verification: .parentApproval)
        #expect(throws: TaskCompletionServiceError.requiresParentApproval(setup.occurrence.id)) {
            try TaskCompletionService(context: setup.context).complete(
                setup.occurrence, at: setup.now, source: .childManual)
        }
        #expect(setup.occurrence.status == .pending)
        try expectCounts(setup.context, completions: 0, xp: 0, coin: 0)
    }

    @Test("脏或外部上下文拒绝，不保存或回滚用户的待提交编辑")
    func foreignAndDirtyContextsArePreserved() throws {
        let setup = try makeSetup()
        let other = ModelContext(setup.context.container)
        #expect(throws: TaskCompletionServiceError.modelNotInContext) {
            try TaskCompletionService(context: other).complete(setup.occurrence, at: setup.now, source: .childManual)
        }
        setup.occurrence.titleSnapshot = "合成待提交编辑"
        #expect(throws: RewardLedgerError.pendingContextChanges) {
            try TaskCompletionService(context: setup.context).complete(
                setup.occurrence, at: setup.now, source: .childManual)
        }
        #expect(setup.context.hasChanges && setup.occurrence.titleSnapshot == "合成待提交编辑")
        try expectCounts(setup.context, completions: 0, xp: 0, coin: 0)
    }

    @Test("已有已撤销历史不拦截新完成，原记录与新事件独立保留")
    func revokedHistoryAllowsNewStableEvent() throws {
        let setup = try makeSetup()
        let historical = CompletionRecord(
            id: V0MigrationFixture.orphanID, occurrenceID: setup.occurrence.id,
            completedAt: setup.now.addingTimeInterval(-100), activeDurationSeconds: 0, completionSource: .childManual,
            createdAt: setup.now.addingTimeInterval(-100), updatedAt: setup.now.addingTimeInterval(-100),
            revokedAt: setup.now.addingTimeInterval(-99))
        setup.context.insert(historical)
        try setup.context.save()
        let result = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence, at: setup.now, source: .childManual)
        #expect(result.didComplete && result.completionID != historical.id && historical.revokedAt != nil)
        #expect(setup.occurrence.completionRecord?.id == result.completionID)
        try expectCounts(setup.context, completions: 2, xp: 1, coin: 1)
    }

    @Test("新结算记录缺账本被拒绝，不用重试补发来掩盖半成功")
    func inconsistentExistingSettlementIsRejected() throws {
        let setup = try makeSetup()
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: setup.now, reminderAt: setup.now,
            xp: 11, baseCoins: 7, autonomyBonusCoins: 3)
        let record = try TaskProgressService(context: setup.context).stageCompletion(
            setup.occurrence, at: setup.now, source: .childManual, rewardSnapshot: snapshot)
        try setup.context.save()
        #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(record.id)) {
            try TaskCompletionService(context: setup.context).complete(
                setup.occurrence, at: setup.now, source: .childManual)
        }
        try expectCounts(setup.context, completions: 1, xp: 0, coin: 0)
    }

    @Test("暂存快照的提交时间不匹配时拒绝，不能持久化相互矛盾的事实")
    func stagingRequiresConsistentSubmissionTime() throws {
        let setup = try makeSetup()
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: setup.now.addingTimeInterval(-1),
            reminderAt: setup.now, xp: 11, baseCoins: 7, autonomyBonusCoins: 3)
        #expect(throws: TaskCompletionServiceError.submissionTimeMismatch(setup.occurrence.id)) {
            try TaskProgressService(context: setup.context).stageCompletion(
                setup.occurrence, at: setup.now, source: .childManual, rewardSnapshot: snapshot)
        }
        #expect(setup.occurrence.status == .pending && !setup.context.hasChanges)
        try expectCounts(setup.context, completions: 0, xp: 0, coin: 0)
    }

    @Test("磁盘重开后再次完成只读原收据，不重复发奖")
    func reopenedCompletionIsIdempotent() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let id = try seedDiskCompletion(at: url)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            let result = try TaskCompletionService(context: context).complete(
                occurrence, at: V0MigrationFixture.instant("2026-09-23T12:00:00Z"), source: .childManual)
            #expect(!result.didComplete && result.completionID == id && result.timing == .beforeReminder)
            #expect(result.xp == 11 && result.coins == 10)
            try expectCounts(context, completions: 1, xp: 1, coin: 1)
        }
    }

    @Test("磁盘保存失败后重开仍是原计时和未完成任务，账本为空")
    func failedDiskCompletionLeavesNoPersistentPartialState() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try failDiskCompletion(at: url)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            try expectUnchangedRunningSetup(context)
        }
    }

    private func makeSetup(
        xp: Int = 11, coins: Int = 7, bonus: Int = 3,
        verification: TaskVerificationType = .selfConfirm, running: Bool = false, storeURL: URL? = nil
    ) throws -> (context: ModelContext, occurrence: TaskOccurrence, now: Date) {
        let container: ModelContainer
        if let storeURL {
            container = try AppModelContainer.make(storeURL: storeURL)
        } else {
            container = try AppModelContainer.make(inMemory: true)
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:30:00Z")
        let occurrence = TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: V0MigrationFixture.templateID,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: now, titleSnapshot: "合成原子完成",
            iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            status: running ? .inProgress : .pending, sourceRevision: 1, createdAt: now, updatedAt: now,
            verificationTypeSnapshot: verification, xpRewardSnapshot: xp, coinRewardSnapshot: coins,
            activeBonusCoinSnapshot: bonus)
        context.insert(occurrence)
        if running {
            let active = TimerSession(
                id: V0MigrationFixture.activeID, occurrenceID: occurrence.id, state: .running,
                startedAt: now.addingTimeInterval(-100), lastResumedAt: now.addingTimeInterval(-50),
                accumulatedActiveSeconds: 100)
            let ended = TimerSession(
                id: V0MigrationFixture.pendingID, occurrenceID: occurrence.id, state: .ended,
                startedAt: now.addingTimeInterval(-400), lastResumedAt: now.addingTimeInterval(-400),
                accumulatedActiveSeconds: 200, endedAt: now.addingTimeInterval(-200))
            context.insert(active)
            context.insert(ended)
            active.occurrence = occurrence
            ended.occurrence = occurrence
        }
        try context.save()
        return (context, occurrence, now)
    }

    private func expectCounts(_ context: ModelContext, completions: Int, xp: Int, coin: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == completions)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == xp)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == coin)
    }

    private func expectUnchangedRunningSetup(_ context: ModelContext) throws {
        let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        #expect(occurrence.status == .inProgress && occurrence.completionRecord == nil)
        let active = try #require(
            context.fetch(FetchDescriptor<TimerSession>()).first { $0.id == V0MigrationFixture.activeID })
        #expect(active.state == .running && active.accumulatedActiveSeconds == 100 && active.endedAt == nil)
        try expectCounts(context, completions: 0, xp: 0, coin: 0)
        #expect(!context.hasChanges)
    }

    private func seedDiskCompletion(at url: URL) throws -> UUID {
        let setup = try makeSetup(running: true, storeURL: url)
        let result = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence, at: setup.now.addingTimeInterval(-1), source: .childManual)
        return result.completionID
    }

    private func failDiskCompletion(at url: URL) throws {
        let setup = try makeSetup(running: true, storeURL: url)
        let service = TaskCompletionService(
            context: setup.context, saveChanges: { _ in throw RewardLedgerError.invalidTimestamp })
        #expect(throws: RewardLedgerError.invalidTimestamp) {
            try service.complete(setup.occurrence, at: setup.now.addingTimeInterval(5), source: .childManual)
        }
        try expectUnchangedRunningSetup(setup.context)
    }
}
