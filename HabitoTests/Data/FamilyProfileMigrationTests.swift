import Foundation
import SwiftData
import Testing
@testable import Habito

/// 仅在临时合成磁盘库验证新增资料结构，不访问正式家庭库或Keychain。
@MainActor
@Suite("名字资料兼容迁移")
struct FamilyProfileMigrationTests {
    @Test("冻结七独立于活跃模型且八只新增两个名字实体")
    func versionEightAddsOnlyTwoNameEntities() throws {
        let old = Schema(versionedSchema: HabitoSchemaV6.self)
        let current = Schema(versionedSchema: HabitoSchemaV7.self)
        #expect(HabitoSchemaV6.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(HabitoSchemaV7.versionIdentifier == Schema.Version(8, 0, 0))
        #expect(old.entities.count == 11 && current.entities.count == 13)
        #expect(Set(current.entities.map(\.name)) == Set(old.entities.map(\.name)).union(["ChildProfile", "Pet"]))
        for entity in old.entities {
            let counterpart = try #require(current.entities.first { $0.name == entity.name })
            #expect(Set(counterpart.properties.map(\.name)) == Set(entity.properties.map(\.name)))
        }
        for (frozen, active) in zip(HabitoSchemaV6.models, HabitoSchemaV7.models) {
            #expect(ObjectIdentifier(frozen) != ObjectIdentifier(active))
        }
        let child = try #require(current.entities.first { $0.name == "ChildProfile" })
        let pet = try #require(current.entities.first { $0.name == "Pet" })
        #expect(Set(child.properties.map(\.name)) == ["singletonKey", "nickname"])
        #expect(Set(pet.properties.map(\.name)) == ["singletonKey", "name"])
        #expect(HabitoSchemaMigrationPlan.schemas.count == 9)
        #expect(HabitoSchemaMigrationPlan.stages.count == 8)
    }

    @Test("旧七完整或空库迁移三次重开不补名字且保留已读语义", arguments: [false, true], [false, true])
    func versionSevenMigrationPreservesFacts(empty: Bool, acknowledged: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V6MigrationFixture.seed(at: url, empty: empty, acknowledged: acknowledged)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            try expectNoProfiles(context)
            if empty {
                #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
            } else {
                try expectVersionSevenFacts(context, acknowledged: acknowledged)
            }
            #expect(!context.hasChanges)
        }
    }

    @Test("更早七版迁移不创建示例档案或增加原交易", arguments: Array(0..<7))
    func allEarlierVersionsKeepProfilesUnconfigured(version: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        switch version {
        case 0: try V0MigrationFixture.seed(at: url)
        case 1: try V1MigrationFixture.seed(at: url)
        case 2: try V2MigrationFixture.seed(at: url)
        case 3: try V3MigrationFixture.seed(at: url)
        case 4: try V4MigrationFixture.seed(at: url)
        case 5: try V5MigrationFixture.seed(at: url)
        default: try V6MigrationFixture.seed(at: url)
        }
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            try expectNoProfiles(context)
            let transactionCount = version >= 3 ? 3 : version == 2 ? 1 : 0
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == transactionCount)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == transactionCount)
            let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
            #expect(settings.hasParentPIN && settings.parentPINCredentialKey == "habito.parent-pin")
            #expect(!context.hasChanges)
        }
    }

    @Test("显式合成名字和固定身份重开保留，不初始化宠物数值或交易")
    func explicitNamesSurviveReopenWithoutOtherWrites() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let names = try FamilyProfileNames(childNickname: "小 星星e\u{301}", petName: "🐶 狗狗")
        try seedNames(at: url, names: names)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            let children = try context.fetch(FetchDescriptor<ChildProfile>())
            let pets = try context.fetch(FetchDescriptor<Pet>())
            #expect(children.count == 1 && pets.count == 1)
            let child = try #require(children.first)
            let pet = try #require(pets.first)
            #expect(child.singletonKey == ChildProfile.defaultKey && pet.singletonKey == Pet.defaultKey)
            #expect(Array(child.nickname.utf8) == Array(names.childNickname.utf8))
            #expect(Array(pet.name.utf8) == Array(names.petName.utf8))
            #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
            #expect(!context.hasChanges)
        }
    }

    private func expectNoProfiles(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 0)
    }

    private func seedNames(at url: URL, names: FamilyProfileNames) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        context.insert(ChildProfile(names: names))
        context.insert(Pet(names: names))
        try context.save()
    }

    private func expectVersionSevenFacts(_ context: ModelContext, acknowledged: Bool) throws {
        let submittedAt = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let settledAt = submittedAt.addingTimeInterval(86400)
        let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
        #expect(
            Set(occurrences.map(\.id)) == [
                V0MigrationFixture.completedID, V0MigrationFixture.pendingID, V0MigrationFixture.activeID,
            ])
        let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
        #expect(template.id == V0MigrationFixture.templateID && template.title == "合成结构七")
        #expect(template.reminderRule?.id == V0MigrationFixture.ruleID)
        #expect(template.reminderRule?.plannedTimeOfDayMinutes == 495)
        #expect(template.reminderRule?.deadlineTimeOfDayMinutes == 560)
        #expect(occurrences.allSatisfy { $0.template?.id == template.id })
        let records = try context.fetch(FetchDescriptor<CompletionRecord>())
        #expect(records.count == 2)
        let receipt = try #require(records.first { $0.id == V0MigrationFixture.orphanID })
        #expect(receipt.occurrence?.id == V0MigrationFixture.completedID)
        #expect(receipt.childFeedbackDeliveryVersion == 1)
        #expect(receipt.childFeedbackAcknowledgedAt == (acknowledged ? settledAt.addingTimeInterval(60) : nil))
        #expect(receipt.completedAt == submittedAt && receipt.rewardSettledAt == settledAt)
        #expect(receipt.submissionID == V6MigrationFixture.approvedID && receipt.rewardSettlementVersion == 2)
        let revoked = try #require(records.first { $0.id == V6MigrationFixture.historicalCompletionID })
        #expect(revoked.revokedAt == submittedAt.addingTimeInterval(-179))
        #expect(revoked.childFeedbackDeliveryVersion == 0 && revoked.childFeedbackAcknowledgedAt == nil)
        for record in records { _ = try TaskCompletionAuditValidator(context: context).validate(record) }
        #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 13, coins: 13))
        #expect(
            Set(try context.fetch(FetchDescriptor<XPTransaction>()).map(\.id))
                == Set(
                    [31, 33, 35].map {
                        V6MigrationFixture.stableID(UInt8($0))
                    }))
        #expect(
            Set(try context.fetch(FetchDescriptor<CoinTransaction>()).map(\.id))
                == Set(
                    [32, 34, 36].map {
                        V6MigrationFixture.stableID(UInt8($0))
                    }))
        let waiting = try #require(occurrences.first { $0.id == V0MigrationFixture.pendingID })
        #expect(try TaskSubmissionHistory(context: context).latest(for: waiting)?.id == V6MigrationFixture.waitingID)
        #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 3)
        let sessions = try context.fetch(FetchDescriptor<TimerSession>())
        #expect(sessions.count == 2 && sessions.contains { $0.state == .paused && $0.accumulatedActiveSeconds == 30 })
        let links = try context.fetch(FetchDescriptor<NotificationLink>())
        #expect(links.count == 2 && links.allSatisfy { $0.occurrence?.id == $0.occurrenceID })
        #expect(links.first { $0.kind == .snooze }?.submissionIDAtScheduling == V6MigrationFixture.approvedID)
        #expect(try context.fetchCount(FetchDescriptor<DayOverride>()) == 1)
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.isOnboardingCompleted && settings.hasParentPIN)
        #expect(settings.parentPINCredentialKey == "habito.parent-pin")
        #expect(settings.lastNotificationSchedulingAt == submittedAt)
        #expect(
            try ChildRewardReceiptService(context: context).pendingReceipts().map(\.completionID)
                == (acknowledged ? [] : [V0MigrationFixture.orphanID]))
    }
}
