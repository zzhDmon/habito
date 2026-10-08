import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Habito

@MainActor
@Suite("小狗主页只读状态")
struct PetProfileViewModelTests {
    @Test("构造不读库，无资料明确未设置且不写入")
    func initialEmptyState() throws {
        let fixture = try TodayQueryFixture()
        var reads = 0
        let model = PetProfileViewModel(loadNames: {
            reads += 1
            return try FamilyProfileService(context: fixture.context).load()
        })
        #expect(reads == 0 && model.state == .loading)
        model.load()
        #expect(reads == 1 && model.state == .notConfigured)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Pet>()) == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("真实保存修改后刷新读到新名字，脏草稿失败且保留，清理可恢复")
    func savedNamesAndPendingEdits() throws {
        let fixture = try TodayQueryFixture()
        let service = FamilyProfileService(context: fixture.context)
        let first = try FamilyProfileNames(childNickname: "小禾", petName: "毛球")
        try service.save(first)
        let model = PetProfileViewModel(loadNames: service.load)
        model.load()
        #expect(model.state == .loaded(first))
        let second = try FamilyProfileNames(childNickname: "小禾", petName: "小云朵")
        try service.save(second)
        model.load()
        #expect(model.state == .loaded(second))
        fixture.context.autosaveEnabled = false
        fixture.context.insert(AppSettings(isOnboardingCompleted: false))
        model.load()
        #expect(model.state == .failed && fixture.context.hasChanges)
        fixture.context.rollback()
        model.load()
        #expect(model.state == .loaded(second))
    }

    @Test("损坏半档案显示失败，不冒充未设置或修库")
    func partialProfileFails() throws {
        let fixture = try TodayQueryFixture()
        fixture.context.insert(ChildProfile(names: try FamilyProfileNames(childNickname: "小禾", petName: "毛球")))
        try fixture.context.save()
        let model = PetProfileViewModel(loadNames: FamilyProfileService(context: fixture.context).load)
        model.load()
        #expect(model.state == .failed)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Pet>()) == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("真实磁盘重开保留名字，儿童读操作不新增实体")
    func diskReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let names = try FamilyProfileNames(childNickname: "合成孩子", petName: "合成小狗")
        try seed(names, at: url)
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        let model = PetProfileViewModel(loadNames: FamilyProfileService(context: context).load)
        model.load()
        #expect(model.state == .loaded(names))
        #expect(try context.fetchCount(FetchDescriptor<Pet>()) == 1)
        #expect(!context.hasChanges)
    }

    @Test("失败探针仅双标志生效且重试恢复真实读取", arguments: [false, true], [false, true])
    func failureProbeRequiresIsolation(isolated: Bool, fail: Bool) throws {
        let fixture = try TodayQueryFixture()
        let arguments =
            (isolated ? [UITestLaunchConfiguration.enableArgument] : [])
            + (fail ? [UITestPetProfileFactory.readFailureArgument] : [])
        let model = UITestPetProfileFactory.make(context: fixture.context, arguments: arguments)
        model.load()
        #expect(model.state == (isolated && fail ? .failed : .notConfigured))
        model.load()
        #expect(model.state == .notConfigured)
    }

    @Test("长名字未设置与错误在普通/MAX深浅色均渲染", arguments: [0, 1, 2], [false, true])
    func rendering(kind: Int, large: Bool) throws {
        let model = PetProfileViewModel(loadNames: {
            if kind == 2 { throw FamilyProfileServiceError.invalidStoredNames }
            return kind == 0
                ? nil : try FamilyProfileNames(childNickname: "孩子", petName: String(repeating: "毛球", count: 20))
        })
        model.load()
        let renderer = ImageRenderer(
            content: PetHomeView(model: model, onOpenParent: {})
                .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                .environment(\.colorScheme, large ? .dark : .light).frame(width: 375, height: 800))
        #expect(try #require(renderer.cgImage).height > 0)
    }

    private func seed(_ names: FamilyProfileNames, at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        try FamilyProfileService(context: context).save(names)
    }
}
