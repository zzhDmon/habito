import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("奖励账本用例")
struct RewardLedgerServiceTests {
    @Test("相同来源重复结算返回原收据，XP 与 Coin 各只有一笔", arguments: [0, 11])
    func retryDoesNotGrantAgain(amount: Int) throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        let now = try instant()
        let first = try service.grantReward(
            sourceID: V0MigrationFixture.completedID, xp: amount, coins: amount, at: now)
        let retry = try service.grantReward(
            sourceID: V0MigrationFixture.completedID, xp: amount, coins: amount,
            at: now.addingTimeInterval(60))
        #expect(first.didInsert && !retry.didInsert && retry.createdAt == now)
        #expect(retry.xpDelta == amount && retry.coinDelta == amount)
        #expect(try service.balance() == RewardBalance(effectiveXP: amount, coins: amount))
        try expectCounts(context, xp: 1, coins: 1)
    }

    @Test("同来源不同 XP 或 Coin 拒绝，不覆盖原金额", arguments: [true, false])
    func conflictingRewardIsRejected(changeXP: Bool) throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        let id = V0MigrationFixture.completedID
        _ = try service.grantReward(sourceID: id, xp: 0, coins: 0, at: instant())
        #expect(throws: RewardLedgerError.businessKeyConflict(RewardLedgerKey.xpReward(id))) {
            try service.grantReward(sourceID: id, xp: changeXP ? 1 : 0, coins: changeXP ? 0 : 1, at: instant())
        }
        #expect(try service.balance() == RewardBalance(effectiveXP: 0, coins: 0))
        try expectCounts(context, xp: 1, coins: 1)
    }

    @Test("负奖励与零负消费拒绝，失败不产生待保存记录", arguments: [-1, 0])
    func invalidAmountsLeaveNoChanges(value: Int) throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        #expect(throws: RewardLedgerError.invalidAmount) {
            try service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: value, at: instant())
        }
        #expect(throws: RewardLedgerError.invalidAmount) {
            try service.grantReward(sourceID: V0MigrationFixture.completedID, xp: -1, coins: 0, at: instant())
        }
        #expect(throws: RewardLedgerError.invalidAmount) {
            try service.grantReward(sourceID: V0MigrationFixture.completedID, xp: 0, coins: -1, at: instant())
        }
        try expectCounts(context, xp: 0, coins: 0)
        #expect(!context.hasChanges)
    }

    @Test("余额不足拒绝消费；恰好全部消费成功且重复不再次扣款")
    func spendingChecksBalanceAndStableEvent() throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        _ = try service.grantReward(sourceID: V0MigrationFixture.completedID, xp: 11, coins: 7, at: instant())
        #expect(throws: RewardLedgerError.insufficientCoins(required: 8, available: 7)) {
            try service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 8, at: instant())
        }
        let first = try service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 7, at: instant())
        let retry = try service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 7, at: instant())
        #expect(first.didInsert && !retry.didInsert && retry.coinDelta == -7)
        #expect(throws: RewardLedgerError.businessKeyConflict(RewardLedgerKey.coinSpend(V0MigrationFixture.pendingID)))
        {
            try service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 6, at: instant())
        }
        #expect(try service.balance() == RewardBalance(effectiveXP: 11, coins: 0))
        try expectCounts(context, xp: 1, coins: 2)
    }

    @Test("冲正保留原记录并恢复有效 XP，重复冲正不再次扣减", arguments: [0, 11])
    func reversalKeepsAuditAndIsIdempotent(amount: Int) throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        let id = V0MigrationFixture.completedID
        let now = try instant()
        _ = try service.grantReward(sourceID: id, xp: amount, coins: amount, at: now)
        let reverse = try service.reverseReward(sourceID: id, at: now.addingTimeInterval(1))
        let retry = try service.reverseReward(sourceID: id, at: now.addingTimeInterval(2))
        #expect(reverse.didInsert && !retry.didInsert && retry.createdAt == reverse.createdAt)
        #expect(reverse.xpDelta == -amount && reverse.coinDelta == -amount)
        #expect(try service.balance() == RewardBalance(effectiveXP: 0, coins: 0))
        let rows = try context.fetch(FetchDescriptor<XPTransaction>())
        #expect(rows.contains { $0.kind == .reward && $0.amount == amount })
        #expect(rows.contains { $0.kind == .reversal && $0.reversalOfBusinessKey == RewardLedgerKey.xpReward(id) })
        // 同一完成事件不能在撤销后重新入账；重新完成必须取得新的完成事件 ID。
        let rewardRetry = try service.grantReward(sourceID: id, xp: amount, coins: amount, at: now)
        #expect(!rewardRetry.didInsert)
        #expect(try service.balance().coins == 0)
        try expectCounts(context, xp: 2, coins: 2)
    }

    @Test("原奖励已消费后冲正拒绝，XP、消费和原收入均保持")
    func insufficientReversalDoesNotPartiallyChangeXP() throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        _ = try service.grantReward(sourceID: V0MigrationFixture.completedID, xp: 11, coins: 7, at: instant())
        _ = try service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 2, at: instant())
        #expect(throws: RewardLedgerError.insufficientCoins(required: 7, available: 5)) {
            try service.reverseReward(sourceID: V0MigrationFixture.completedID, at: instant())
        }
        #expect(try service.balance() == RewardBalance(effectiveXP: 11, coins: 5))
        try expectCounts(context, xp: 1, coins: 2)
        #expect(!context.hasChanges)
    }

    @Test("找不到原收入和时间倒退拒绝，不捏造冲正")
    func reversalRequiresOriginalRewardAndValidTime() throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        let id = V0MigrationFixture.completedID
        let now = try instant()
        #expect(throws: RewardLedgerError.rewardNotFound(id)) { try service.reverseReward(sourceID: id, at: now) }
        _ = try service.grantReward(sourceID: id, xp: 11, coins: 7, at: now)
        #expect(throws: RewardLedgerError.timeBeforeReward) {
            try service.reverseReward(sourceID: id, at: now.addingTimeInterval(-1))
        }
        try expectCounts(context, xp: 1, coins: 1)
    }

    @Test("非有限注入时间拒绝，不保存无效事实")
    func nonFiniteTimeIsRejected() throws {
        let context = try makeContext()
        #expect(throws: RewardLedgerError.invalidTimestamp) {
            try RewardLedgerService(context: context).grantReward(
                sourceID: V0MigrationFixture.completedID,
                xp: 11, coins: 7, at: Date(timeIntervalSinceReferenceDate: .infinity))
        }
        try expectCounts(context, xp: 0, coins: 0)
    }

    @Test("XP 或 Coin 总额溢出拒绝，两边都不半写入", arguments: [true, false])
    func overflowRejectsBothAssetRows(xpOverflows: Bool) throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        _ = try service.grantReward(
            sourceID: V0MigrationFixture.completedID,
            xp: xpOverflows ? Int.max : 0, coins: xpOverflows ? 0 : Int.max, at: instant())
        #expect(throws: RewardLedgerError.integerOverflow) {
            try service.grantReward(sourceID: V0MigrationFixture.pendingID, xp: 1, coins: 1, at: instant())
        }
        try expectCounts(context, xp: 1, coins: 1)
        #expect(!context.hasChanges)
    }

    @Test("异号交易抵消后不会因读取顺序误报溢出", arguments: [true, false])
    func checkedSumIsIndependentOfFetchOrder(reverseOrder: Bool) throws {
        let amounts = [Int.max, Int.max, -Int.max]
        #expect(try RewardBalance.checkedTotal(reverseOrder ? amounts.reversed().map { $0 } : amounts) == Int.max)
        #expect(throws: RewardLedgerError.integerOverflow) { try RewardBalance.checkedTotal([Int.max, 1]) }
        #expect(throws: RewardLedgerError.integerOverflow) { try RewardBalance.checkedTotal([Int.min, -1]) }
    }

    @Test("收入消费冲正保存失败均回滚，原余额和自动保存设置保持", arguments: ["reward", "spend", "reversal"])
    func saveFailureRollsBackOnlyNewTransaction(operation: String) throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        _ = try service.grantReward(sourceID: V0MigrationFixture.completedID, xp: 11, coins: 7, at: instant())
        context.autosaveEnabled = true
        let originalAutosave = context.autosaveEnabled
        let failing = RewardLedgerService(
            context: context, saveChanges: { _ in throw RewardLedgerError.invalidTimestamp })
        #expect(throws: RewardLedgerError.invalidTimestamp) {
            switch operation {
            case "spend":
                _ = try failing.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 2, at: instant())
            case "reversal":
                _ = try failing.reverseReward(sourceID: V0MigrationFixture.completedID, at: instant())
            default:
                _ = try failing.grantReward(sourceID: V0MigrationFixture.pendingID, xp: 5, coins: 3, at: instant())
            }
        }
        #expect(try service.balance() == RewardBalance(effectiveXP: 11, coins: 7))
        try expectCounts(context, xp: 1, coins: 1)
        #expect(!context.hasChanges && context.autosaveEnabled == originalAutosave)
    }

    @Test("有未保存用户编辑时独立事务拒绝，不保存也不回滚用户编辑")
    func dirtyContextIsPreserved() throws {
        let context = try makeContext()
        let settings = AppSettings(isOnboardingCompleted: true)
        context.insert(settings)
        #expect(throws: RewardLedgerError.pendingContextChanges) {
            try RewardLedgerService(context: context).grantReward(
                sourceID: V0MigrationFixture.completedID,
                xp: 11, coins: 7, at: instant())
        }
        #expect(context.hasChanges && settings.isOnboardingCompleted)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
        try expectCounts(context, xp: 0, coins: 0)
    }

    @Test("事务暂存入口可与其他事实一起保存，尚未保存结果不当到账")
    func stagedRowsCanJoinOuterTransaction() throws {
        let context = try makeContext()
        context.insert(AppSettings(isOnboardingCompleted: true))
        let result = try RewardLedgerService(context: context).stageReward(
            sourceID: V0MigrationFixture.completedID, xp: 11, coins: 7, at: instant())
        #expect(result.didInsert && context.hasChanges)
        try context.save()
        #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 11, coins: 7))
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test("单边或非法符号交易明确拒绝，不忽略损坏继续发奖", arguments: [true, false])
    func malformedAuditIsRejected(missingPartner: Bool) throws {
        let context = try makeContext()
        let id = V0MigrationFixture.completedID
        context.insert(
            XPTransaction(
                businessKey: RewardLedgerKey.xpReward(id), sourceID: id,
                kind: .reward, amount: missingPartner ? 11 : -11, createdAt: try instant()))
        if !missingPartner {
            context.insert(
                CoinTransaction(
                    businessKey: RewardLedgerKey.coinReward(id), sourceID: id,
                    kind: .reward, amount: 7, createdAt: try instant()))
        }
        try context.save()
        #expect(throws: RewardLedgerError.corruptLedger(RewardLedgerKey.xpReward(id))) {
            try RewardLedgerService(context: context).balance()
        }
    }

    @Test("磁盘重开继续派生余额，重复收入消费和冲正都不增行")
    func persistedLedgerKeepsIdempotenceAcrossContexts() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try seedLedger(at: url)
        for _ in 0..<3 { try verifyReopenedLedger(at: url) }
    }

    @Test("冲正金额不精确对应原交易时拒绝，不把错误冲正当真实余额", arguments: [true, false])
    func malformedReversalIsRejected(invalidXP: Bool) throws {
        let context = try makeContext()
        let id = V0MigrationFixture.completedID
        _ = try RewardLedgerService(context: context).grantReward(sourceID: id, xp: 11, coins: 7, at: instant())
        context.insert(
            XPTransaction(
                businessKey: RewardLedgerKey.xpReversal(id), sourceID: id, kind: .reversal,
                amount: invalidXP ? -10 : -11, reversalOfBusinessKey: RewardLedgerKey.xpReward(id),
                createdAt: try instant()))
        context.insert(
            CoinTransaction(
                businessKey: RewardLedgerKey.coinReversal(id), sourceID: id, kind: .reversal,
                amount: invalidXP ? -7 : -6, reversalOfBusinessKey: RewardLedgerKey.coinReward(id),
                createdAt: try instant()))
        try context.save()
        let key = invalidXP ? RewardLedgerKey.xpReversal(id) : RewardLedgerKey.coinReversal(id)
        #expect(throws: RewardLedgerError.corruptLedger(key)) { try RewardLedgerService(context: context).balance() }
    }

    @Test("负余额或非规范业务键拒绝，损坏账本不继续写入", arguments: [true, false])
    func invalidSpendAuditIsRejected(negativeBalance: Bool) throws {
        let context = try makeContext()
        let service = RewardLedgerService(context: context)
        _ = try service.grantReward(sourceID: V0MigrationFixture.completedID, xp: 11, coins: 7, at: instant())
        let key = negativeBalance ? RewardLedgerKey.coinSpend(V0MigrationFixture.pendingID) : "malformed-key"
        context.insert(
            CoinTransaction(
                businessKey: key, sourceID: V0MigrationFixture.pendingID,
                kind: .spend, amount: negativeBalance ? -8 : -2, createdAt: try instant()))
        try context.save()
        #expect(throws: RewardLedgerError.corruptLedger(negativeBalance ? "negative-balance" : key)) {
            try service.grantReward(sourceID: V0MigrationFixture.activeID, xp: 1, coins: 1, at: instant())
        }
        try expectCounts(context, xp: 1, coins: 2)
        #expect(!context.hasChanges)
    }

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        context.autosaveEnabled = false
        return context
    }

    private func instant() throws -> Date { try V0MigrationFixture.instant("2026-09-22T11:29:00Z") }

    private func expectCounts(_ context: ModelContext, xp: Int, coins: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == xp)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == coins)
    }

    private func seedLedger(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let service = RewardLedgerService(context: context)
        _ = try service.grantReward(sourceID: V0MigrationFixture.completedID, xp: 11, coins: 10, at: instant())
        _ = try service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 3, at: instant())
        _ = try service.grantReward(sourceID: V0MigrationFixture.activeID, xp: 5, coins: 6, at: instant())
        _ = try service.reverseReward(sourceID: V0MigrationFixture.completedID, at: instant())
    }

    private func verifyReopenedLedger(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let service = RewardLedgerService(context: context)
        #expect(try service.balance() == RewardBalance(effectiveXP: 5, coins: 3))
        #expect(
            try !service.grantReward(sourceID: V0MigrationFixture.completedID, xp: 11, coins: 10, at: instant())
                .didInsert)
        #expect(try !service.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 3, at: instant()).didInsert)
        #expect(try !service.reverseReward(sourceID: V0MigrationFixture.completedID, at: instant()).didInsert)
        try expectCounts(context, xp: 3, coins: 4)
    }
}
