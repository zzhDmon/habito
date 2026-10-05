import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("保留完成事实的审计撤销")
struct TaskCompletionUndoServiceTests {
    @Test("五秒内可撤销，相等与超出窗口拒绝", arguments: [0.0, 4.999, 5.0, 5.001])
    func undoUsesStrictExistingWindow(offset: TimeInterval) throws {
        let setup = try makeSetup()
        let service = TaskCompletionUndoService(context: setup.context)
        if offset < 5 {
            let result = try service.undo(
                setup.occurrence, completionID: setup.completionID,
                at: setup.completedAt.addingTimeInterval(offset))
            #expect(result.didUndo && result.xpDelta == -11 && result.coinDelta == -10)
            #expect(setup.occurrence.status == .pending && setup.occurrence.completionRecord == nil)
            let record = try #require(setup.context.fetch(FetchDescriptor<CompletionRecord>()).first)
            #expect(record.id == setup.completionID && record.revokedAt == result.revokedAt)
            #expect(record.occurrence == nil && record.completionTiming == .beforeReminder)
            #expect(record.xpRewardSnapshot == 11 && record.settledCoinSnapshot == 10)
            #expect(
                try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
            try expectCounts(setup.context, completions: 1, xp: 2, coin: 2)
        } else {
            #expect(throws: TaskCompletionUndoError.undoWindowExpired(setup.completionID)) {
                try service.undo(
                    setup.occurrence, completionID: setup.completionID,
                    at: setup.completedAt.addingTimeInterval(offset))
            }
            try expectOriginalCompletion(setup.context, completionID: setup.completionID)
        }
    }

    @Test("时钟倒退拒绝，不因为页面倒计时变长而延长撤销")
    func backwardsTimeIsRejected() throws {
        let setup = try makeSetup()
        #expect(throws: TaskProgressServiceError.timeBeforeCompletion(occurrenceID: setup.occurrence.id)) {
            try TaskCompletionUndoService(context: setup.context).undo(
                setup.occurrence,
                completionID: setup.completionID, at: setup.completedAt.addingTimeInterval(-1))
        }
        try expectOriginalCompletion(setup.context, completionID: setup.completionID)
    }

    @Test("重复撤销只返回原时刻，窗口外重试不新增冲正")
    func retryKeepsOriginalRevocation() throws {
        let setup = try makeSetup()
        let service = TaskCompletionUndoService(context: setup.context)
        let first = try service.undo(
            setup.occurrence, completionID: setup.completionID,
            at: setup.completedAt.addingTimeInterval(1))
        let retry = try service.undo(
            setup.occurrence, completionID: setup.completionID,
            at: setup.completedAt.addingTimeInterval(1000))
        #expect(first.didUndo && !retry.didUndo && retry.revokedAt == first.revokedAt)
        #expect(retry.xpDelta == first.xpDelta && retry.coinDelta == first.coinDelta)
        try expectCounts(setup.context, completions: 1, xp: 2, coin: 2)
    }

    @Test("原奖励已消费且币不足时整次撤销拒绝，消费与 XP 原样保持")
    func insufficientCoinsPreserveAllFacts() throws {
        let setup = try makeSetup()
        _ = try RewardLedgerService(context: setup.context).spendCoins(
            sourceID: V0MigrationFixture.pendingID,
            cost: 2, at: setup.completedAt)
        #expect(throws: RewardLedgerError.insufficientCoins(required: 10, available: 8)) {
            try TaskCompletionUndoService(context: setup.context).undo(
                setup.occurrence,
                completionID: setup.completionID, at: setup.completedAt.addingTimeInterval(1))
        }
        #expect(setup.occurrence.status == .completed && setup.occurrence.completionRecord?.revokedAt == nil)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 11, coins: 8))
        try expectCounts(setup.context, completions: 1, xp: 1, coin: 2)
        #expect(!setup.context.hasChanges)
    }

    @Test("总余额足够可冲正，原消费不删除，有效 XP 按剩余账本重算")
    func sufficientOtherBalanceAllowsExactReversal() throws {
        let setup = try makeSetup()
        let ledger = RewardLedgerService(context: setup.context)
        _ = try ledger.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 2, at: setup.completedAt)
        _ = try ledger.grantReward(sourceID: V0MigrationFixture.orphanID, xp: 5, coins: 3, at: setup.completedAt)
        _ = try TaskCompletionUndoService(context: setup.context).undo(
            setup.occurrence,
            completionID: setup.completionID, at: setup.completedAt.addingTimeInterval(1))
        #expect(try ledger.balance() == RewardBalance(effectiveXP: 5, coins: 1))
        #expect(
            try setup.context.fetch(FetchDescriptor<CoinTransaction>()).contains {
                $0.kind == .spend && $0.amount == -2
            })
        try expectCounts(setup.context, completions: 1, xp: 3, coin: 4)
    }

    @Test("零奖励也保留原事实与零冲正，不扣成负余额")
    func zeroRewardUndoKeepsAudit() throws {
        let setup = try makeSetup(xp: 0, coins: 0, bonus: 0)
        let result = try TaskCompletionUndoService(context: setup.context).undo(
            setup.occurrence,
            completionID: setup.completionID, at: setup.completedAt.addingTimeInterval(1))
        #expect(result.xpDelta == 0 && result.coinDelta == 0 && result.didUndo)
        try expectCounts(setup.context, completions: 1, xp: 2, coin: 2)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
    }

    @Test("旧无奖励完成撤销只保留历史，不捏造交易")
    func legacyUnsettledUndoDoesNotInventReversal() throws {
        let setup = try makeSetup(legacy: true)
        let result = try TaskCompletionUndoService(context: setup.context).undo(
            setup.occurrence,
            completionID: setup.completionID, at: setup.completedAt.addingTimeInterval(1))
        let record = try #require(setup.context.fetch(FetchDescriptor<CompletionRecord>()).first)
        #expect(result.xpDelta == 0 && result.coinDelta == 0 && record.revokedAt != nil)
        #expect(record.rewardSettlementVersion == 0 && record.completionTiming == .unknown)
        try expectCounts(setup.context, completions: 1, xp: 0, coin: 0)
    }

    @Test("旧记录若有明确原账则冲正原账，不从新模板金额推断")
    func legacyKnownTransactionsAreReversedWithoutBackfill() throws {
        let setup = try makeSetup(legacy: true)
        _ = try RewardLedgerService(context: setup.context).grantReward(
            sourceID: setup.completionID,
            xp: 13, coins: 9, at: setup.completedAt)
        let result = try TaskCompletionUndoService(context: setup.context).undo(
            setup.occurrence,
            completionID: setup.completionID, at: setup.completedAt.addingTimeInterval(1))
        #expect(result.xpDelta == -13 && result.coinDelta == -9)
        let record = try #require(setup.context.fetch(FetchDescriptor<CompletionRecord>()).first)
        #expect(record.xpRewardSnapshot == 0 && record.reminderAtSnapshot == nil && record.completionTiming == .unknown)
        try expectCounts(setup.context, completions: 1, xp: 2, coin: 2)
    }

    @Test("再次完成保留两条事实，旧撤销请求不会误伤新完成或奖励")
    func retryOfOldUndoCannotRevokeNewCompletion() throws {
        let setup = try makeSetup(running: true)
        let undo = TaskCompletionUndoService(context: setup.context)
        _ = try undo.undo(
            setup.occurrence, completionID: setup.completionID,
            at: setup.completedAt.addingTimeInterval(1))
        _ = try TaskProgressService(context: setup.context).startTiming(
            for: setup.occurrence,
            at: setup.completedAt.addingTimeInterval(1.5))
        let new = try TaskCompletionService(context: setup.context).complete(
            setup.occurrence,
            at: setup.completedAt.addingTimeInterval(2), source: .childManual)
        let retry = try undo.undo(
            setup.occurrence, completionID: setup.completionID,
            at: setup.completedAt.addingTimeInterval(3))
        #expect(!retry.didUndo && new.completionID != setup.completionID)
        #expect(setup.occurrence.status == .completed && setup.occurrence.completionRecord?.id == new.completionID)
        #expect(setup.occurrence.completionRecord?.activeDurationSeconds == 40.5)
        #expect(try RewardLedgerService(context: setup.context).balance() == RewardBalance(effectiveXP: 11, coins: 7))
        try expectCounts(setup.context, completions: 2, xp: 3, coin: 3)
    }

    @Test("保存失败恢复完成关系与状态，撤销标记和冲正都不留下")
    func failedUndoRestoresOriginalGraph() throws {
        let setup = try makeSetup(running: true)
        let service = TaskCompletionUndoService(
            context: setup.context,
            saveChanges: { _ in throw RewardLedgerError.invalidTimestamp })
        #expect(throws: RewardLedgerError.invalidTimestamp) {
            try service.undo(
                setup.occurrence, completionID: setup.completionID,
                at: setup.completedAt.addingTimeInterval(1))
        }
        try expectOriginalCompletion(setup.context, completionID: setup.completionID)
        #expect(setup.occurrence.completionRecord?.activeDurationSeconds == 40)
        let session = try #require(setup.context.fetch(FetchDescriptor<TimerSession>()).first)
        #expect(session.state == .ended && session.accumulatedActiveSeconds == 40)
    }

    @Test("不认识的原完成 ID 拒绝，不转而撤销当前记录")
    func unknownCompletionRequestIsRejected() throws {
        let setup = try makeSetup()
        #expect(throws: TaskCompletionUndoError.completionNotFound(V0MigrationFixture.pendingID)) {
            try TaskCompletionUndoService(context: setup.context).undo(
                setup.occurrence,
                completionID: V0MigrationFixture.pendingID, at: setup.completedAt)
        }
        try expectOriginalCompletion(setup.context, completionID: setup.completionID)
    }

    @Test("有撤销标记但缺反向账被拒绝，不伪装成已安全撤销")
    func revokedMarkerWithoutReversalIsRejected() throws {
        let setup = try makeSetup()
        let record = try #require(setup.occurrence.completionRecord)
        record.revokedAt = setup.completedAt.addingTimeInterval(1)
        try setup.context.save()
        #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(record.id)) {
            try TaskCompletionUndoService(context: setup.context).undo(
                setup.occurrence,
                completionID: record.id, at: setup.completedAt.addingTimeInterval(2))
        }
        try expectCounts(setup.context, completions: 1, xp: 1, coin: 1)
    }

    @Test("外上下文与未保存编辑拒绝，用户编辑不丢失")
    func dirtyAndForeignContextsArePreserved() throws {
        let setup = try makeSetup()
        let other = ModelContext(setup.context.container)
        #expect(throws: TaskCompletionServiceError.modelNotInContext) {
            try TaskCompletionUndoService(context: other).undo(
                setup.occurrence,
                completionID: setup.completionID, at: setup.completedAt)
        }
        setup.occurrence.titleSnapshot = "合成用户待提交"
        #expect(throws: RewardLedgerError.pendingContextChanges) {
            try TaskCompletionUndoService(context: setup.context).undo(
                setup.occurrence,
                completionID: setup.completionID, at: setup.completedAt)
        }
        #expect(setup.context.hasChanges && setup.occurrence.titleSnapshot == "合成用户待提交")
    }

    @Test("磁盘重开保留撤销事实并保持冲正幂等，失败磁盘不半写入", arguments: [true, false])
    func diskUndoKeepsAtomicAudit(shouldFail: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let id = try seedDiskUndo(at: url, shouldFail: shouldFail)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            if shouldFail {
                try expectOriginalCompletion(context, completionID: id)
            } else {
                let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
                let result = try TaskCompletionUndoService(context: context).undo(
                    occurrence,
                    completionID: id, at: V0MigrationFixture.instant("2026-09-23T12:00:00Z"))
                #expect(!result.didUndo && occurrence.status == .pending)
                try expectCounts(context, completions: 1, xp: 2, coin: 2)
                #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
            }
        }
    }

    private func makeSetup(
        xp: Int = 11, coins: Int = 7, bonus: Int = 3,
        running: Bool = false, legacy: Bool = false, storeURL: URL? = nil
    ) throws -> (context: ModelContext, occurrence: TaskOccurrence, completedAt: Date, completionID: UUID) {
        let container: ModelContainer
        if let storeURL {
            container = try AppModelContainer.make(storeURL: storeURL)
        } else {
            container = try AppModelContainer.make(inMemory: true)
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let completedAt = try V0MigrationFixture.instant("2026-09-22T11:29:59Z")
        let occurrence = TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: V0MigrationFixture.templateID,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: completedAt.addingTimeInterval(1),
            titleSnapshot: "合成审计撤销", iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            status: running ? .inProgress : .pending, sourceRevision: 1, createdAt: completedAt, updatedAt: completedAt,
            xpRewardSnapshot: xp, coinRewardSnapshot: coins, activeBonusCoinSnapshot: bonus)
        context.insert(occurrence)
        if running {
            let session = TimerSession(
                id: V0MigrationFixture.activeID, occurrenceID: occurrence.id, state: .running,
                startedAt: completedAt.addingTimeInterval(-10), lastResumedAt: completedAt.addingTimeInterval(-10),
                accumulatedActiveSeconds: 30)
            context.insert(session)
            session.occurrence = occurrence
        }
        try context.save()
        let id: UUID
        if legacy {
            id = try TaskProgressService(context: context).complete(occurrence, at: completedAt, source: .childManual)
                .id
        } else {
            id = try TaskCompletionService(context: context).complete(occurrence, at: completedAt, source: .childManual)
                .completionID
        }
        return (context, occurrence, completedAt, id)
    }

    private func expectCounts(_ context: ModelContext, completions: Int, xp: Int, coin: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == completions)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == xp)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == coin)
    }

    private func expectOriginalCompletion(_ context: ModelContext, completionID: UUID) throws {
        let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        let record = try #require(context.fetch(FetchDescriptor<CompletionRecord>()).first)
        #expect(occurrence.status == .completed && occurrence.completionRecord?.id == completionID)
        #expect(record.id == completionID && record.revokedAt == nil && record.occurrence?.id == occurrence.id)
        #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
        try expectCounts(context, completions: 1, xp: 1, coin: 1)
        #expect(!context.hasChanges)
    }

    private func seedDiskUndo(at url: URL, shouldFail: Bool) throws -> UUID {
        let setup = try makeSetup(running: true, storeURL: url)
        let service = TaskCompletionUndoService(
            context: setup.context,
            saveChanges: shouldFail ? { _ in throw RewardLedgerError.invalidTimestamp } : { try $0.save() })
        if shouldFail {
            #expect(throws: RewardLedgerError.invalidTimestamp) {
                try service.undo(
                    setup.occurrence, completionID: setup.completionID,
                    at: setup.completedAt.addingTimeInterval(1))
            }
            try expectOriginalCompletion(setup.context, completionID: setup.completionID)
        } else {
            _ = try service.undo(
                setup.occurrence, completionID: setup.completionID,
                at: setup.completedAt.addingTimeInterval(1))
        }
        return setup.completionID
    }
}
