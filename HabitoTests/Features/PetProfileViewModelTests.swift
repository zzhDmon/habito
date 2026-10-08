import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Habito

@MainActor
@Suite("小狗成长与喂食状态")
struct PetProfileViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_791_421_200)

    @Test("构造不读库，无资料明确未设置且不写入")
    func initialEmptyState() throws {
        let context = try context()
        let care = service(context)
        var reads = 0
        let model = PetProfileViewModel(
            loadSnapshot: { date in
                reads += 1; return try care.load(at: date)
            },
            feedPet: care.feed, now: { now })
        #expect(reads == 0 && model.state == .loading)
        model.load()
        #expect(reads == 1 && model.state == .notConfigured)
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 0 && !context.hasChanges)
    }

    @Test("真实保存修改后刷新，脏草稿失败保留且清理可恢复")
    func savedNamesAndPendingEdits() throws {
        let context = try context()
        let profiles = FamilyProfileService(context: context)
        let first = try FamilyProfileNames(childNickname: "小禾", petName: "毛球")
        try profiles.save(first)
        let model = model(context)
        model.load()
        #expect(names(model) == first)
        let second = try FamilyProfileNames(childNickname: "小禾", petName: "小云朵")
        try profiles.save(second)
        model.load()
        #expect(names(model) == second)
        context.insert(AppSettings())
        model.load()
        #expect(model.state == .failed && context.hasChanges)
        context.rollback()
        model.load()
        #expect(names(model) == second)
    }

    @Test("损坏半档案显示失败，不冒充未设置或修库")
    func partialProfileFails() throws {
        let context = try context()
        context.insert(ChildProfile(names: try FamilyProfileNames(childNickname: "小禾", petName: "毛球")))
        try context.save()
        let model = model(context)
        model.load()
        #expect(model.state == .failed)
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 0 && !context.hasChanges)
    }

    @Test("真实磁盘重开保留名字，儿童读取不新增实体")
    func diskReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let expected = try FamilyProfileNames(childNickname: "合成孩子", petName: "合成小狗")
        try seed(expected, at: url)
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        let model = model(context)
        model.load()
        #expect(names(model) == expected)
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 1 && !context.hasChanges)
    }

    @Test("读取失败探针仅双标志生效且重试恢复", arguments: [false, true], [false, true])
    func failureProbeRequiresIsolation(isolated: Bool, fail: Bool) throws {
        let context = try context()
        let arguments =
            (isolated ? [UITestLaunchConfiguration.enableArgument] : [])
            + (fail ? [UITestPetProfileFactory.readFailureArgument] : [])
        let model = UITestPetProfileFactory.make(
            context: context, arguments: arguments,
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt, now: { now })
        model.load()
        #expect(model.state == (isolated && fail ? .failed : .notConfigured))
        model.load()
        #expect(model.state == .notConfigured)
    }

    @Test("失败喂食重试复用请求ID，成功后连续点击不二扣")
    func feedRetryAndRepeatedTap() throws {
        let context = try fundedContext()
        let care = service(context)
        var fail = true
        var ids: [UUID] = []
        let model = PetProfileViewModel(
            loadSnapshot: care.load,
            feedPet: { id, date in
                ids.append(id)
                if fail { fail = false; throw CocoaError(.fileWriteUnknown) }
                return try care.feed(requestID: id, at: date)
            }, now: { now })
        model.load(); model.feed()
        #expect(model.feedingError == .saveFailed && model.feedingReceipt == nil)
        #expect(try care.load(at: now)?.coins == 12)
        model.feed()
        #expect(ids.count == 2 && ids[0] == ids[1])
        #expect(model.feedingReceipt?.didInsert == true && model.feedingError == nil)
        model.feed()
        #expect(ids.count == 2)
        #expect(try care.load(at: now)?.coins == 7)
        model.dismissFeedingReceipt(); model.feed()
        #expect(ids.count == 3 && ids[2] != ids[1])
        #expect(try care.load(at: now)?.coins == 2)
        model.load()
        #expect(model.feedingReceipt == nil)
    }

    @Test("双标志保存失败探针一次失败不扣款且可恢复", arguments: [false, true], [false, true])
    func feedingFailureProbe(isolated: Bool, fail: Bool) throws {
        let context = try fundedContext()
        let arguments =
            (isolated ? [UITestLaunchConfiguration.enableArgument] : [])
            + (fail ? [UITestPetProfileFactory.feedFailureArgument] : [])
        let model = UITestPetProfileFactory.make(
            context: context, arguments: arguments,
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt, now: { now })
        model.load(); model.feed()
        if isolated && fail {
            #expect(model.feedingError == .saveFailed && model.feedingReceipt == nil)
            #expect(try service(context).load(at: now)?.coins == 12)
            model.feed()
        }
        #expect(model.feedingReceipt?.didInsert == true)
        #expect(try service(context).load(at: now)?.coins == 7)
    }

    @Test("陈旧余额不够时显示明确失败并刷新真实余额")
    func staleBalanceCannotPurchase() throws {
        let context = try fundedContext()
        let model = model(context)
        model.load()
        _ = try RewardLedgerService(context: context).spendCoins(sourceID: UUID(), cost: 10, at: now)
        model.feed()
        #expect(model.feedingError == .insufficientCoins && model.feedingReceipt == nil)
        guard case let .loaded(snapshot) = model.state else { Issue.record("应保留最新快照"); return }
        #expect(snapshot.coins == 2 && !snapshot.canFeed && snapshot.bond == 0)
    }

    @Test("保存成功后读取失败仍保留成功收据，不能伪报没扣款")
    func postSaveReadFailureKeepsReceipt() throws {
        let context = try fundedContext()
        let care = service(context)
        var reads = 0
        let model = PetProfileViewModel(
            loadSnapshot: { date in
                reads += 1
                if reads > 1 { throw CocoaError(.fileReadUnknown) }
                return try care.load(at: date)
            }, feedPet: care.feed, now: { now })
        model.load(); model.feed()
        #expect(model.state == .failed && model.feedingReceipt?.didInsert == true && model.feedingError == nil)
        #expect(try care.load(at: now)?.coins == 7)
    }

    @Test("正常未设置与错误在普通/MAX深浅色均可渲染", arguments: [0, 1, 2], [false, true])
    func rendering(kind: Int, large: Bool) throws {
        let model = PetPreviewData.model(kind: kind)
        model.load()
        let renderer = ImageRenderer(
            content: PetHomeView(model: model, onOpenParent: {})
                .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                .environment(\.colorScheme, large ? .dark : .light).frame(width: 375, height: 800))
        #expect(try #require(renderer.cgImage).height > 0)
    }

    private func context() throws -> ModelContext {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        context.autosaveEnabled = false
        return context
    }
    private func fundedContext() throws -> ModelContext {
        let context = try context()
        try FamilyProfileService(context: context).save(FamilyProfileNames(childNickname: "合成孩子", petName: "合成小狗"))
        _ = try RewardLedgerService(context: context).grantReward(sourceID: UUID(), xp: 95, coins: 12, at: now)
        return context
    }
    private func service(_ context: ModelContext) -> PetCareService {
        PetCareService(context: context, calendar: Calendar(identifier: .gregorian), timeZone: .gmt)
    }
    private func model(_ context: ModelContext) -> PetProfileViewModel {
        let care = service(context)
        return PetProfileViewModel(loadSnapshot: care.load, feedPet: care.feed, now: { now })
    }
    private func names(_ model: PetProfileViewModel) -> FamilyProfileNames? {
        guard case let .loaded(snapshot) = model.state else { return nil }
        return snapshot.names
    }
    private func seed(_ names: FamilyProfileNames, at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        try FamilyProfileService(context: context).save(names)
    }
}
