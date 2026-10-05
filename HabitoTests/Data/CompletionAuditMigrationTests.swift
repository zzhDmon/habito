import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("完成快照与撤销审计迁移")
struct CompletionAuditMigrationTests {
    @Test("独立 V0 和两版 V1 迁移重开，不改写旧完成或已有账本", arguments: [0, 1, 2])
    func previousStoresKeepHistoryWithoutBackfilling(version: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        switch version {
        case 0: try V0MigrationFixture.seed(at: url)
        case 1: try V1MigrationFixture.seed(at: url)
        default: try V2MigrationFixture.seed(at: url)
        }
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let records = try context.fetch(FetchDescriptor<CompletionRecord>())
            #expect(records.count == (version == 0 ? 2 : 1))
            for record in records {
                #expect(record.reminderAtSnapshot == nil && record.revokedAt == nil)
                #expect(record.xpRewardSnapshot == 0 && record.coinRewardSnapshot == 0)
                #expect(record.activeBonusCoinSnapshot == 0 && record.settledCoinSnapshot == 0)
                #expect(record.rewardSettlementVersion == 0)
                #expect(record.completionTiming == (version == 0 ? .unknown : .beforeReminder))
            }
            let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
            let completed = try #require(occurrences.first { $0.id == V0MigrationFixture.completedID })
            #expect(completed.completionRecord?.occurrence?.id == completed.id)
            #expect(
                completed.completionRecord?.completedAt
                    == (try V0MigrationFixture.instant(version == 0 ? "2026-09-21T11:45:00Z" : "2026-09-22T11:29:00Z")))
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == (version == 2 ? 1 : 0))
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == (version == 2 ? 1 : 0))
            if version == 2 {
                let balance = try RewardLedgerService(context: context).balance()
                #expect(balance == RewardBalance(effectiveXP: 11, coins: 10))
                let row = try #require(context.fetch(FetchDescriptor<XPTransaction>()).first)
                #expect(row.sourceID == V0MigrationFixture.orphanID)
                #expect(row.id == V0MigrationFixture.activeID && row.amount == 11)
                #expect(row.businessKey == RewardLedgerKey.xpReward(V0MigrationFixture.orphanID))
            }
        }
    }

    @Test("同实例撤销历史和新完成可共存，重开不 upsert 丢失原事实")
    func revokedAndActiveRecordsCoexistAcrossReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V2MigrationFixture.seed(at: url)
        try seedSyntheticSecondCompletion(at: url)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let records = try context.fetch(FetchDescriptor<CompletionRecord>())
            #expect(records.count == 2)
            #expect(records.allSatisfy { $0.occurrenceID == V0MigrationFixture.completedID })
            let historical = try #require(records.first { $0.id == V0MigrationFixture.orphanID })
            let active = try #require(records.first { $0.id == V0MigrationFixture.activeID })
            #expect(historical.revokedAt == (try V0MigrationFixture.instant("2026-09-22T11:29:30Z")))
            #expect(historical.occurrence == nil && historical.activeDurationSeconds == 900)
            #expect(historical.completedAt == (try V0MigrationFixture.instant("2026-09-22T11:29:00Z")))
            #expect(historical.rewardSettlementVersion == 0 && historical.completionTiming == .beforeReminder)
            #expect(active.revokedAt == nil && active.rewardSettlementVersion == 1)
            #expect(active.reminderAtSnapshot == (try V0MigrationFixture.instant("2026-09-22T11:30:00Z")))
            #expect(active.xpRewardSnapshot == 11 && active.coinRewardSnapshot == 7)
            #expect(active.activeBonusCoinSnapshot == 3 && active.settledCoinSnapshot == 10)
            #expect(active.completionTiming == .beforeReminder && active.activeDurationSeconds == 1200)
            let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            #expect(occurrence.completionRecord?.id == active.id && active.occurrence?.id == occurrence.id)
            #expect(occurrence.xpRewardSnapshot == 99 && occurrence.coinRewardSnapshot == 88)
            #expect(occurrence.activeBonusCoinSnapshot == 77)
            #expect(occurrence.scheduledAt == (try V0MigrationFixture.instant("2026-09-22T12:00:00Z")))
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 1)
        }
    }

    /// 只验证结构，不冒充真实撤销/再次完成事务；后续卡必须接账本和计时原子用例。
    private func seedSyntheticSecondCompletion(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        let historical = try #require(occurrence.completionRecord)
        historical.revokedAt = try V0MigrationFixture.instant("2026-09-22T11:29:30Z")
        historical.occurrence = nil
        occurrence.completionRecord = nil
        let submittedAt = try V0MigrationFixture.instant("2026-09-22T11:29:45Z")
        let active = CompletionRecord(
            id: V0MigrationFixture.activeID, occurrenceID: occurrence.id,
            completedAt: submittedAt, activeDurationSeconds: 1200, completionSource: .childManual,
            createdAt: submittedAt, updatedAt: submittedAt, completionTiming: .beforeReminder,
            reminderAtSnapshot: try V0MigrationFixture.instant("2026-09-22T11:30:00Z"),
            xpRewardSnapshot: 11, coinRewardSnapshot: 7, activeBonusCoinSnapshot: 3, settledCoinSnapshot: 10,
            rewardSettlementVersion: 1)
        context.insert(active)
        active.occurrence = occurrence
        occurrence.completionRecord = active
        try context.save()
        // 后续改单日配置不能改写已提交快照；这里只改实例，不修改只读完成快照。
        occurrence.scheduledAt = try V0MigrationFixture.instant("2026-09-22T12:00:00Z")
        occurrence.xpRewardSnapshot = 99
        occurrence.coinRewardSnapshot = 88
        occurrence.activeBonusCoinSnapshot = 77
        try context.save()
    }
}
