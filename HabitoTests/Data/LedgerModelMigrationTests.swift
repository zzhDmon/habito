import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("空账本迁移与交易审计持久化")
struct LedgerModelMigrationTests {
    @Test("V0 迁移到当前版本保留任务图且不补奖", arguments: [true, false])
    func legacyMigrationDoesNotMintRewards(versioned: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V0MigrationFixture.seed(at: url, versioned: versioned)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 4)
            #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 2)
            #expect(try context.fetchCount(FetchDescriptor<TimerSession>()) == 2)
            try expectEmptyLedger(context)
        }
    }

    @Test("上一版非零配置与完成快照保持，迁移和重开不发奖励")
    func configuredPreviousVersionRemainsUnsettled() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V1MigrationFixture.seed(at: url)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
            let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            let completion = try #require(occurrence.completionRecord)
            #expect(template.id == V0MigrationFixture.templateID && template.category == .growth)
            #expect(template.timePeriod == .afterSchool && template.verificationType == .parentApproval)
            #expect(template.xpReward == 11 && template.coinReward == 7 && template.activeBonusCoin == 3)
            #expect(occurrence.id == V0MigrationFixture.completedID && occurrence.template?.id == template.id)
            #expect(occurrence.xpRewardSnapshot == 11 && occurrence.coinRewardSnapshot == 7)
            #expect(occurrence.activeBonusCoinSnapshot == 3 && occurrence.status == .completed)
            #expect(occurrence.categorySnapshot == .growth && occurrence.timePeriodSnapshot == .afterSchool)
            #expect(occurrence.verificationTypeSnapshot == .parentApproval)
            #expect(occurrence.plannedAt == (try V0MigrationFixture.instant("2026-09-22T11:00:00Z")))
            #expect(occurrence.scheduledAt == (try V0MigrationFixture.instant("2026-09-22T11:30:00Z")))
            #expect(occurrence.deadlineAt == (try V0MigrationFixture.instant("2026-09-22T12:00:00Z")))
            #expect(template.reminderRule?.plannedTimeOfDayMinutes == 1140)
            #expect(template.reminderRule?.deadlineTimeOfDayMinutes == 1200)
            #expect(completion.id == V0MigrationFixture.orphanID && completion.completionTiming == .beforeReminder)
            #expect(completion.completedAt == (try V0MigrationFixture.instant("2026-09-22T11:29:00Z")))
            let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
            #expect(settings.hasParentPIN && settings.parentPINCredentialKey == AppSettings.parentPINKeychainAccount)
            try expectEmptyLedger(context)
        }
    }

    @Test("显式交易重开后保留身份、来源、金额与冲正关联")
    func transactionsSurviveDiskReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try seedTransactions(at: url)
        for _ in 0..<2 { try verifyTransactions(at: url) }
    }

    @Test("物理删除合成任务图不级联删除已发生的交易")
    func deletedTaskGraphKeepsAuditTransactions() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V1MigrationFixture.seed(at: url)
        try seedTransactions(at: url)
        try deleteSyntheticOccurrence(at: url)
        try verifyTransactions(at: url)
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    }

    private func expectEmptyLedger(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }

    private func seedTransactions(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        context.insert(
            XPTransaction(
                id: V0MigrationFixture.activeID, businessKey: "fixture:xp:reward",
                sourceID: V0MigrationFixture.orphanID, kind: .reward, amount: 11, createdAt: now))
        context.insert(
            XPTransaction(
                id: V0MigrationFixture.pendingID, businessKey: "fixture:xp:reverse",
                sourceID: V0MigrationFixture.orphanID, kind: .reversal, amount: -11,
                reversalOfBusinessKey: "fixture:xp:reward", createdAt: now))
        context.insert(
            CoinTransaction(
                id: V0MigrationFixture.activeID, businessKey: "fixture:coin:reward",
                sourceID: V0MigrationFixture.orphanID, kind: .reward, amount: 7, createdAt: now))
        context.insert(
            CoinTransaction(
                id: V0MigrationFixture.pendingID, businessKey: "fixture:coin:spend",
                sourceID: V0MigrationFixture.pendingID, kind: .spend, amount: -2, createdAt: now))
        context.insert(
            CoinTransaction(
                id: V0MigrationFixture.ruleID, businessKey: "fixture:coin:reverse",
                sourceID: V0MigrationFixture.orphanID, kind: .reversal, amount: -7,
                reversalOfBusinessKey: "fixture:coin:reward", createdAt: now))
        // 这里只测试模型存储能力；该合成负余额不是业务写入口，余额限制在下一卡验证。
        try context.save()
    }

    private func verifyTransactions(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        let xp = try context.fetch(FetchDescriptor<XPTransaction>())
        let coin = try context.fetch(FetchDescriptor<CoinTransaction>())
        #expect(xp.count == 2 && coin.count == 3)
        let reward = try #require(xp.first { $0.businessKey == "fixture:xp:reward" })
        #expect(reward.id == V0MigrationFixture.activeID && reward.sourceID == V0MigrationFixture.orphanID)
        #expect(reward.kind == .reward && reward.amount == 11 && reward.reversalOfBusinessKey == nil)
        #expect(reward.createdAt == (try V0MigrationFixture.instant("2026-09-22T11:29:00Z")))
        let reversal = try #require(xp.first { $0.kind == .reversal })
        #expect(reversal.amount == -11 && reversal.reversalOfBusinessKey == reward.businessKey)
        #expect(reversal.id == V0MigrationFixture.pendingID && reversal.sourceID == reward.sourceID)
        let spend = try #require(coin.first { $0.kind == .spend })
        #expect(spend.amount == -2 && spend.businessKey == "fixture:coin:spend")
        #expect(spend.sourceID == V0MigrationFixture.pendingID && spend.reversalOfBusinessKey == nil)
        let coinReward = try #require(coin.first { $0.kind == .reward })
        let coinReversal = try #require(coin.first { $0.kind == .reversal })
        #expect(coinReward.amount == 7 && coinReversal.amount == -7)
        #expect(coinReversal.reversalOfBusinessKey == coinReward.businessKey)
        #expect(coinReversal.sourceID == coinReward.sourceID)
    }

    private func deleteSyntheticOccurrence(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        try TaskGraphDeletionService(context: context).stageOccurrenceDeletion(occurrence)
        try context.save()
    }
}
