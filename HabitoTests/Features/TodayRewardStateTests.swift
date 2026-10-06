import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("儿童资产只读状态")
struct TodayRewardStateTests {
    private let rewardID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    private let spendID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    private let extraRewardID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))

    @Test("空账本与旧零奖励完成都展示真实零资产，不补发历史", arguments: [false, true])
    func emptyLedgerDoesNotInferRewardsFromHistory(legacy: Bool) throws {
        let fixture = try TodayQueryFixture()
        fixture.context.autosaveEnabled = false
        if legacy {
            let occurrence = fixture.makeOccurrence(title: "旧任务", scheduledAt: fixture.now, status: .completed)
            fixture.addCompletion(to: occurrence, at: fixture.now)
        }
        try fixture.context.save()
        let model = makeModel(fixture)
        #expect(model.rewardState == .loading)
        model.load()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        try expectLedgerCounts(fixture.context, xp: 0, coins: 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("真实完成与撤销刷新精确资产，重复读取不写账", arguments: [0, 11, Int.max])
    func completionAndUndoUseSavedBalance(amount: Int) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "显式奖励", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.xpRewardSnapshot = amount
        occurrence.coinRewardSnapshot = amount
        try fixture.context.save()
        let model = makeModel(fixture)
        let receipt = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        for _ in 0..<3 { model.load() }
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: amount, coins: amount)))
        try expectLedgerCounts(fixture.context, xp: 1, coins: 1)
        #expect(!fixture.context.hasChanges)
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: receipt.completionID, at: fixture.now.addingTimeInterval(1))
        model.load()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        try expectLedgerCounts(fixture.context, xp: 2, coins: 2)
        #expect(!fixture.context.hasChanges)
    }

    @Test("等待与退回不显示预期奖励，重提通过后只显示已保存金额")
    func reviewCycleLoadsOnlyConfirmedReward() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "审核奖励", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        occurrence.xpRewardSnapshot = 11
        occurrence.coinRewardSnapshot = 7
        occurrence.activeBonusCoinSnapshot = 3
        try fixture.context.save()
        let model = makeModel(fixture)
        let submission = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        model.load()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
            occurrence, submissionID: submission.submissionID, at: fixture.now.addingTimeInterval(1))
        model.load()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        // 第二次提交晚于提醒，真实通过是基础 7 Coin，不从第一次自主提交推算成 10。
        let second = try TaskSubmissionService(context: fixture.context).submit(
            occurrence, at: fixture.now.addingTimeInterval(120))
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: second.submissionID, at: fixture.now.addingTimeInterval(121))
        for _ in 0..<3 { model.load() }
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 11, coins: 7)))
        try expectLedgerCounts(fixture.context, xp: 1, coins: 1)
        #expect(!fixture.context.hasChanges)
    }

    @Test("消费与审计冲正刷新有效余额，不把累计收入当可用金币")
    func spendingAndReversalUseEffectiveLedgerBalance() throws {
        let fixture = try TodayQueryFixture()
        let ledger = RewardLedgerService(context: fixture.context)
        _ = try ledger.grantReward(sourceID: rewardID, xp: 11, coins: 7, at: fixture.now)
        _ = try ledger.spendCoins(sourceID: spendID, cost: 3, at: fixture.now)
        let model = makeModel(fixture)
        model.load()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 11, coins: 4)))
        #expect(throws: RewardLedgerError.insufficientCoins(required: 7, available: 4)) {
            try ledger.reverseReward(sourceID: rewardID, at: fixture.now.addingTimeInterval(1))
        }
        model.loadRewards()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 11, coins: 4)))
        _ = try ledger.grantReward(sourceID: extraRewardID, xp: 4, coins: 4, at: fixture.now)
        _ = try ledger.reverseReward(sourceID: rewardID, at: fixture.now.addingTimeInterval(1))
        model.loadRewards()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 4, coins: 1)))
        try expectLedgerCounts(fixture.context, xp: 3, coins: 4)
        #expect(!fixture.context.hasChanges)
    }

    @Test("损坏账本明确失败，任务仍可加载且没有自动修账", arguments: [false, true])
    func corruptLedgerDoesNotHideTasksOrInventZero(missingPartner: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "可做任务", scheduledAt: fixture.now, status: .pending)
        fixture.context.insert(
            XPTransaction(
                businessKey: RewardLedgerKey.xpReward(rewardID), sourceID: rewardID,
                kind: .reward, amount: missingPartner ? 11 : -1, createdAt: fixture.now))
        if !missingPartner {
            fixture.context.insert(
                CoinTransaction(
                    businessKey: RewardLedgerKey.coinReward(rewardID), sourceID: rewardID,
                    kind: .reward, amount: 7, createdAt: fixture.now))
        }
        try fixture.context.save()
        let model = makeModel(fixture)
        model.load()
        #expect(model.rewardState == .failed)
        let content = try #require(loadedContent(model.state))
        #expect(content.recommendedTask?.id == occurrence.id)
        try expectLedgerCounts(fixture.context, xp: 1, coins: missingPartner ? 0 : 1)
        #expect(!fixture.context.hasChanges)
    }

    @Test("暂存交易或其他编辑均不显示到账，不替调用方保存或回滚", arguments: [false, true])
    func pendingChangesPreserveCallerOwnershipAndCanRecover(stagedReward: Bool) throws {
        let fixture = try TodayQueryFixture()
        fixture.context.autosaveEnabled = false
        let occurrence = fixture.makeOccurrence(title: "原任务", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        let model = makeModel(fixture)
        model.load()
        let originalTaskState = model.state
        if stagedReward {
            _ = try RewardLedgerService(context: fixture.context).stageReward(
                sourceID: rewardID, xp: 11, coins: 7, at: fixture.now)
        } else {
            occurrence.titleSnapshot = "未保存编辑"
        }
        model.loadRewards()
        #expect(model.rewardState == .failed && fixture.context.hasChanges)
        #expect(model.state == originalTaskState)
        if stagedReward {
            try expectLedgerCounts(fixture.context, xp: 1, coins: 1)
        } else {
            #expect(occurrence.titleSnapshot == "未保存编辑")
        }
        // 只有测试调用方清理其独占内存夹具，页面只读入口不能代替用户做这个决定。
        fixture.context.rollback()
        model.loadRewards()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        #expect(model.state == originalTaskState)
        try expectLedgerCounts(fixture.context, xp: 0, coins: 0)
    }

    @Test("任务查询失败也独立读取真实资产，不把两类错误混成零余额")
    func taskFailureDoesNotInvalidateHealthyLedger() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "坏状态", scheduledAt: fixture.now, status: .pending)
        occurrence.statusRawValue = "invalid"
        try fixture.context.save()
        _ = try RewardLedgerService(context: fixture.context).grantReward(
            sourceID: rewardID, xp: 11, coins: 7, at: fixture.now)
        let model = makeModel(fixture)
        model.load()
        #expect(model.state == .failed)
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 11, coins: 7)))
        #expect(!fixture.context.hasChanges)
    }

    @Test("保存失败的奖励不进入资产展示，读取不重试结算")
    func failedSaveNeverPublishesUnsavedReward() throws {
        let fixture = try TodayQueryFixture()
        let ledger = RewardLedgerService(context: fixture.context) { _ in throw CocoaError(.fileWriteUnknown) }
        #expect(throws: CocoaError.self) {
            try ledger.grantReward(sourceID: rewardID, xp: 11, coins: 7, at: fixture.now)
        }
        let model = makeModel(fixture)
        model.load()
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        try expectLedgerCounts(fixture.context, xp: 0, coins: 0)
        #expect(!fixture.context.hasChanges)
    }

    private func makeModel(_ fixture: TodayQueryFixture) -> TodayViewModel {
        TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now))
    }

    private func expectLedgerCounts(_ context: ModelContext, xp: Int, coins: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == xp)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == coins)
    }

    private func loadedContent(_ state: TodayViewState) -> TodayScreenContent? {
        guard case let .loaded(content) = state else { return nil }
        return content
    }
}
