import Foundation
import SwiftData
import Testing
@testable import Habito

/// 迁移证据全部来自固定合成磁盘库；不访问正式家庭容器或真实Keychain。
@MainActor
@Suite("宠物事实兼容结构")
struct PetFactMigrationTests {
    @Test("冻结八独立于活跃模型，九仅增加喂食与观察点")
    func versionNineAddsOnlyPetFacts() throws {
        let old = Schema(versionedSchema: HabitoSchemaV7.self)
        let current = AppModelContainer.schema
        #expect(HabitoSchemaV8.versionIdentifier == Schema.Version(9, 0, 0))
        #expect(old.entities.count == 13 && current.entities.count == 15)
        #expect(
            Set(current.entities.map(\.name))
                == Set(old.entities.map(\.name)).union(["PetFeeding", "PetGrowthCheckpoint"]))
        for entity in old.entities {
            let active = try #require(current.entities.first { $0.name == entity.name })
            #expect(Set(entity.properties.map(\.name)) == Set(active.properties.map(\.name)))
        }
        for (oldType, activeType) in zip(HabitoSchemaV7.models, HabitoSchemaV8.models) {
            #expect(ObjectIdentifier(oldType) != ObjectIdentifier(activeType))
        }
        #expect(HabitoSchemaMigrationPlan.schemas.count == 9)
        #expect(HabitoSchemaMigrationPlan.stages.count == 8)
    }

    @Test("独立旧八资料及审核账本三次重开保持，不回填宠物事实", arguments: [false, true], [false, true])
    func namedLegacyStorePreservesFacts(configured: Bool, acknowledged: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V7MigrationFixture.seed(at: url, acknowledged: acknowledged, configured: configured)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            let names = try FamilyProfileService(context: context).load()
            #expect((names != nil) == configured)
            if configured {
                #expect(names?.childNickname.utf8.elementsEqual("小星e\u{301}".utf8) == true)
                #expect(names?.petName == "奶油🐶")
            }
            #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 13, coins: 13))
            let records = try context.fetch(FetchDescriptor<CompletionRecord>())
            #expect(records.count == 2)
            for record in records { _ = try TaskCompletionAuditValidator(context: context).validate(record) }
            #expect(try ChildRewardReceiptService(context: context).pendingReceipts().count == (acknowledged ? 0 : 1))
            let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
            #expect(template.id == V0MigrationFixture.templateID && template.title == "合成结构八")
            #expect(template.reminderRule?.taskTemplate?.id == template.id)
            #expect(template.reminderRule?.plannedTimeOfDayMinutes == 495)
            let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
            #expect(occurrences.count == 3 && occurrences.allSatisfy { $0.template?.id == template.id })
            #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 3)
            let sessions = try context.fetch(FetchDescriptor<TimerSession>())
            #expect(
                sessions.count == 2 && sessions.contains { $0.state == .paused && $0.accumulatedActiveSeconds == 30 })
            let links = try context.fetch(FetchDescriptor<NotificationLink>())
            #expect(links.count == 2 && links.allSatisfy { $0.occurrence?.id == $0.occurrenceID })
            #expect(
                try context.fetch(FetchDescriptor<AppSettings>()).first?.parentPINCredentialKey == "habito.parent-pin")
            #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<PetGrowthCheckpoint>()) == 0)
            #expect(!context.hasChanges)
        }
    }

    @Test("旧八空库迁移不创建档案、喂食或成长基线")
    func emptyStoreHasNoPetFacts() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V7MigrationFixture.seed(at: url, empty: true)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            #expect(try FamilyProfileService(context: context).load() == nil)
            #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<PetGrowthCheckpoint>()) == 0)
            #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        }
    }

    @Test("新宠物事实及稳定消费关联磁盘重开保持")
    func savedPetFactsSurviveReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let id = V7MigrationFixture.stableID(99)
        let now = try V0MigrationFixture.instant("2026-10-08T01:00:00Z")
        try seedPetFacts(at: url, id: id, now: now)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let feeding = try #require(context.fetch(FetchDescriptor<PetFeeding>()).first)
            #expect(feeding.id == id && feeding.petKey == Pet.defaultKey)
            #expect(
                feeding.foodID == "kibble" && feeding.coinCost == 5 && feeding.bondGain == 1 && feeding.createdAt == now
            )
            let checkpoint = try #require(context.fetch(FetchDescriptor<PetGrowthCheckpoint>()).first)
            #expect(checkpoint.petKey == Pet.defaultKey && checkpoint.observedLevel == 2)
            #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 113, coins: 8))
            #expect(!context.hasChanges)
        }
    }

    private func seedPetFacts(at url: URL, id: UUID, now: Date) throws {
        try V7MigrationFixture.seed(at: url)
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let ledger = RewardLedgerService(context: context)
        _ = try ledger.grantReward(sourceID: V7MigrationFixture.stableID(98), xp: 100, coins: 0, at: now)
        _ = try ledger.stageSpend(sourceID: id, cost: 5, at: now)
        context.insert(
            PetFeeding(id: id, petKey: Pet.defaultKey, foodID: "kibble", coinCost: 5, bondGain: 1, createdAt: now))
        context.insert(PetGrowthCheckpoint(petKey: Pet.defaultKey, observedLevel: 2))
        try context.save()
    }
}
