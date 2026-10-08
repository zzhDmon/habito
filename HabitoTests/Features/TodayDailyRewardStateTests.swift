import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Habito

@MainActor
@Suite("今日所得状态与展示")
struct TodayDailyRewardStateTests {
    @Test("真实完成撤销更新所得，重新载入不写账")
    func savedCompletionAndUndo() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "所得", scheduledAt: fixture.now, status: .pending)
        occurrence.xpRewardSnapshot = 11
        occurrence.coinRewardSnapshot = 7
        try fixture.context.save()
        let model = model(fixture)
        #expect(model.dailyRewardState == .loading)
        let receipt = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        model.load()
        #expect(model.dailyRewardState == .loaded(DailyRewardSummary(earnedXP: 11, earnedCoins: 7)))
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: receipt.completionID, at: fixture.now.addingTimeInterval(1))
        model.loadRewards()
        #expect(model.dailyRewardState == .loaded(DailyRewardSummary(earnedXP: 0, earnedCoins: 0)))
        #expect(!fixture.context.hasChanges)
    }

    @Test("跨日旧奖和今日消费不混进今日收入，累计余额独立")
    func dailyIncomeAndWalletDiffer() throws {
        let fixture = try TodayQueryFixture()
        let ledger = RewardLedgerService(context: fixture.context)
        _ = try ledger.grantReward(
            sourceID: V0MigrationFixture.completedID, xp: 20, coins: 10, at: fixture.now.addingTimeInterval(-86400))
        _ = try ledger.grantReward(sourceID: V0MigrationFixture.activeID, xp: 11, coins: 7, at: fixture.now)
        _ = try ledger.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: 3, at: fixture.now)
        let model = model(fixture)
        for _ in 0..<3 { model.load() }
        #expect(model.dailyRewardState == .loaded(DailyRewardSummary(earnedXP: 11, earnedCoins: 7)))
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 31, coins: 14)))
        #expect(!fixture.context.hasChanges)
    }

    @Test("今日收入溢出不隐藏健康余额和任务，单独重试不改钱包")
    func independentFailure() throws {
        let fixture = try TodayQueryFixture()
        let ledger = RewardLedgerService(context: fixture.context)
        _ = try ledger.grantReward(sourceID: V0MigrationFixture.completedID, xp: 0, coins: Int.max, at: fixture.now)
        _ = try ledger.spendCoins(sourceID: V0MigrationFixture.pendingID, cost: Int.max, at: fixture.now)
        _ = try ledger.grantReward(sourceID: V0MigrationFixture.activeID, xp: 0, coins: 1, at: fixture.now)
        let model = model(fixture)
        model.load()
        #expect(model.dailyRewardState == .failed)
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 1)))
        #expect(model.state != .failed)
        model.loadDailyRewards()
        #expect(model.dailyRewardState == .failed)
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 1)))
    }

    @Test("失败撤去旧所得，脏编辑不代保存且清理后可重试")
    func failureRemovesStaleIncomeAndRecovers() throws {
        let fixture = try TodayQueryFixture()
        fixture.context.autosaveEnabled = false
        let model = model(fixture)
        model.load()
        fixture.context.insert(AppSettings(isOnboardingCompleted: false))
        model.loadDailyRewards()
        #expect(model.dailyRewardState == .failed && fixture.context.hasChanges)
        fixture.context.rollback()
        model.loadDailyRewards()
        #expect(model.dailyRewardState == .loaded(DailyRewardSummary(earnedXP: 0, earnedCoins: 0)))
    }

    @Test("零值大整数及错误在普通MAX和深浅色均可渲染", arguments: [0, 11, Int.max, -1], [false, true])
    func render(amount: Int, large: Bool) throws {
        let state: TodayDailyRewardState =
            amount < 0 ? .failed : .loaded(DailyRewardSummary(earnedXP: amount, earnedCoins: amount))
        let renderer = ImageRenderer(
            content: KidTodayDailyRewardView(state: state, onRetry: {})
                .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                .environment(\.colorScheme, large ? .dark : .light).frame(width: 320))
        #expect(try #require(renderer.cgImage).height > 0)
    }

    private func model(_ fixture: TodayQueryFixture) -> TodayViewModel {
        TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now))
    }
}
