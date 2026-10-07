import Foundation
import SwiftData
import Testing
@testable import Habito

/// 所有输入为固定合成资料，只有显式临时磁盘URL，不访问家庭容器或Keychain。
@MainActor
@Suite("名字加载与原子保存")
struct FamilyProfileServiceTests {
    @Test("未设置只读返回空，不创建资料或调用保存")
    func unconfiguredLoadDoesNotWrite() throws {
        let context = try makeContext()
        let service = FamilyProfileService(
            context: context,
            saveChanges: { _ in
                Issue.record("只读不能调用保存")
            })
        for _ in 0..<3 { #expect(try service.load() == nil) }
        #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test("创建两字段只保存一次且同值重试幂等", arguments: [false, true])
    func creationSavesOnceAndRetriesAreIdempotent(autosave: Bool) throws {
        let context = try makeContext()
        context.autosaveEnabled = autosave
        var saveCount = 0
        let service = FamilyProfileService(
            context: context,
            saveChanges: { context in
                saveCount += 1
                #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 1)
                #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 1)
                #expect(!context.autosaveEnabled)
                try context.save()
            })
        let value = try names()
        #expect(try service.save(value))
        for _ in 0..<3 { #expect(try !service.save(value)) }
        #expect(saveCount == 1 && context.autosaveEnabled == autosave)
        #expect(try service.load() == value && !context.hasChanges)
        try expectNoOtherRecords(context)
    }

    @Test("更新两个名字保留模型身份并仅保存一次")
    func updatePreservesIdentityAndSavesBothFields() throws {
        let context = try makeContext()
        let normal = FamilyProfileService(context: context)
        try normal.save(names())
        let child = try #require(context.fetch(FetchDescriptor<ChildProfile>()).first)
        let pet = try #require(context.fetch(FetchDescriptor<Pet>()).first)
        let childID = child.persistentModelID
        let petID = pet.persistentModelID
        let updated = try names(updated: true)
        var saves = 0
        let service = FamilyProfileService(
            context: context,
            saveChanges: { context in
                saves += 1
                #expect(child.nickname == updated.childNickname && pet.name == updated.petName)
                try context.save()
            })
        #expect(try service.save(updated))
        #expect(try !service.save(updated))
        #expect(saves == 1 && child.persistentModelID == childID && pet.persistentModelID == petID)
        #expect(try normal.load() == updated && !context.hasChanges)
        try expectNoOtherRecords(context)
    }

    @Test("等价Unicode的显式新表示按原始字节保存")
    func equivalentUnicodeStillPreservesNewInputBytes() throws {
        let context = try makeContext()
        let service = FamilyProfileService(context: context)
        let original = try FamilyProfileNames(childNickname: "é", petName: "🐶")
        let updated = try FamilyProfileNames(childNickname: "e\u{301}", petName: "🐶")
        #expect(original == updated)
        try service.save(original)
        #expect(try service.save(updated))
        let loaded = try #require(try service.load())
        #expect(Array(loaded.childNickname.utf8) == Array(updated.childNickname.utf8))
        #expect(try !service.save(updated))
    }

    @Test("脏上下文拒绝读写且不提交或回滚别人编辑")
    func dirtyContextIsPreserved() throws {
        let context = try makeContext()
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        settings.isOnboardingCompleted = true
        let service = FamilyProfileService(
            context: context,
            saveChanges: { _ in
                Issue.record("脏编辑不能保存")
            })
        #expect(throws: FamilyProfileServiceError.pendingContextChanges) { try service.load() }
        #expect(throws: FamilyProfileServiceError.pendingContextChanges) { try service.save(names()) }
        #expect(context.hasChanges && settings.isOnboardingCompleted)
        #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 0)
    }

    @Test("半档案明确拒绝，不用新输入掩盖不完整存储", arguments: [false, true])
    func partialProfilesAreRejected(childOnly: Bool) throws {
        let context = try makeContext()
        let value = try names()
        if childOnly { context.insert(ChildProfile(names: value)) } else { context.insert(Pet(names: value)) }
        try context.save()
        let service = FamilyProfileService(context: context)
        #expect(throws: FamilyProfileServiceError.inconsistentStoredProfiles) { try service.load() }
        #expect(throws: FamilyProfileServiceError.inconsistentStoredProfiles) { try service.save(names(updated: true)) }
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == (childOnly ? 1 : 0))
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == (childOnly ? 0 : 1))
    }

    @Test("错误业务键或重复资料拒绝读写", arguments: [false, true], [false, true])
    func invalidIdentityAndDuplicateProfilesAreRejected(childField: Bool, duplicate: Bool) throws {
        let context = try makeContext()
        let value = try names()
        try FamilyProfileService(context: context).save(value)
        if childField {
            let child =
                duplicate
                ? ChildProfile(names: value) : try #require(context.fetch(FetchDescriptor<ChildProfile>()).first)
            // 仅合成损坏夹具使用SwiftData底层写入口，不向生产模型开放无校验setter。
            child.setValue(forKey: \.singletonKey, to: "habito.synthetic.invalid-child")
            if duplicate { context.insert(child) }
        } else {
            let pet = duplicate ? Pet(names: value) : try #require(context.fetch(FetchDescriptor<Pet>()).first)
            pet.setValue(forKey: \.singletonKey, to: "habito.synthetic.invalid-pet")
            if duplicate { context.insert(pet) }
        }
        try context.save()
        let service = FamilyProfileService(context: context)
        #expect(throws: FamilyProfileServiceError.inconsistentStoredProfiles) { try service.load() }
        #expect(throws: FamilyProfileServiceError.inconsistentStoredProfiles) { try service.save(names(updated: true)) }
        #expect(!context.hasChanges)
    }

    @Test("非法或未清理存储名字拒绝读取与覆盖", arguments: [false, true], ["", "坏\n名字", "名字 "])
    func invalidStoredNamesAreRejected(childField: Bool, invalid: String) throws {
        let context = try makeContext()
        try FamilyProfileService(context: context).save(names())
        if childField {
            let child = try #require(context.fetch(FetchDescriptor<ChildProfile>()).first)
            child.setValue(forKey: \.nickname, to: invalid)
        } else {
            let pet = try #require(context.fetch(FetchDescriptor<Pet>()).first)
            pet.setValue(forKey: \.name, to: invalid)
        }
        try context.save()
        let service = FamilyProfileService(context: context)
        #expect(throws: FamilyProfileServiceError.invalidStoredNames) { try service.load() }
        #expect(throws: FamilyProfileServiceError.invalidStoredNames) { try service.save(names(updated: true)) }
        #expect(!context.hasChanges)
    }

    @Test("创建失败不留下任一资料且恢复autosave，可重试", arguments: [false, true])
    func failedCreationRestoresUnconfiguredState(autosave: Bool) throws {
        let context = try makeContext()
        context.autosaveEnabled = autosave
        let service = failingService(context)
        #expect(throws: NSError.self) { try service.save(names()) }
        #expect(!context.hasChanges && context.autosaveEnabled == autosave)
        let normal = FamilyProfileService(context: context)
        #expect(try normal.load() == nil)
        #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 0)
        #expect(try normal.save(names()))
        #expect(try normal.load() == names())
    }

    @Test("更新失败恢复活跃两个旧字段和autosave，可重试", arguments: [false, true])
    func failedUpdateRestoresBothActiveValues(autosave: Bool) throws {
        let context = try makeContext()
        let old = try names()
        let normal = FamilyProfileService(context: context)
        try normal.save(old)
        let child = try #require(context.fetch(FetchDescriptor<ChildProfile>()).first)
        let pet = try #require(context.fetch(FetchDescriptor<Pet>()).first)
        context.autosaveEnabled = autosave
        #expect(throws: NSError.self) { try failingService(context).save(names(updated: true)) }
        #expect(child.nickname == old.childNickname && pet.name == old.petName)
        #expect(!context.hasChanges && context.autosaveEnabled == autosave)
        #expect(try normal.load() == old)
        #expect(try normal.save(names(updated: true)))
        #expect(try normal.load() == names(updated: true))
    }

    @Test("合成磁盘创建或更新失败保留旧事实，多次重开后重试", arguments: [false, true])
    func failedDiskSavePreservesOldConfiguration(updating: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        if updating { try saveNames(at: url, value: names()) }
        try failDiskSave(at: url)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let service = FamilyProfileService(context: context)
            #expect(try service.load() == (updating ? names() : nil))
            #expect(!context.hasChanges)
        }
        try saveNames(at: url, value: names(updated: true))
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        #expect(try FamilyProfileService(context: context).load() == names(updated: true))
    }

    @Test("独立旧七迁移后显式保存和更新，原收据账本PIN通知保持")
    func migratedStoreCanSaveAndUpdateWithoutChangingBusinessFacts() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V6MigrationFixture.seed(at: url, acknowledged: true)
        try saveNames(at: url, value: names())
        try saveNames(at: url, value: names(updated: true))
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            #expect(try FamilyProfileService(context: context).load() == names(updated: true))
            #expect(try context.fetchCount(FetchDescriptor<ChildProfile>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 1)
            #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 13, coins: 13))
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 3)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 3)
            #expect(try ChildRewardReceiptService(context: context).pendingReceipts().isEmpty)
            #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 3)
            #expect(try context.fetchCount(FetchDescriptor<NotificationLink>()) == 2)
            let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
            #expect(settings.isOnboardingCompleted && settings.parentPINCredentialKey == "habito.parent-pin")
            #expect(!context.hasChanges)
        }
    }

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        context.autosaveEnabled = false
        return context
    }

    private func names(updated: Bool = false) throws -> FamilyProfileNames {
        try FamilyProfileNames(childNickname: updated ? "新 小星星" : "小 星星", petName: updated ? "新🐶狗狗" : "🐶狗狗")
    }

    private func failingService(_ context: ModelContext) -> FamilyProfileService {
        FamilyProfileService(
            context: context,
            saveChanges: { _ in
                throw NSError(domain: "HabitoSyntheticProfileSave", code: 1)
            })
    }

    private func saveNames(at url: URL, value: FamilyProfileNames) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        try FamilyProfileService(context: context).save(value)
    }

    private func failDiskSave(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        #expect(throws: NSError.self) { try failingService(context).save(names(updated: true)) }
        #expect(!context.hasChanges)
    }

    private func expectNoOtherRecords(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }
}
