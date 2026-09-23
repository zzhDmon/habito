import SwiftData
import Testing
@testable import Habito

@Suite("家长门禁状态")
@MainActor
struct ParentGateViewModelTests {
    @Test("首次展示进入创建且两次不一致不写凭据")
    func firstPresentationAndMismatch() throws {
        let fixture = try makeFixture()

        fixture.model.prepareForPresentation()
        #expect(fixture.model.state == .setup)

        fixture.model.createPIN("1357", confirmation: "2468")
        #expect(fixture.model.feedback == .confirmationMismatch)
        #expect(fixture.store.storedPIN == nil)
    }

    @Test("创建后重开要求验证且错误与正确 PIN 分流")
    func createReopenAndVerify() throws {
        let fixture = try makeFixture()
        fixture.model.prepareForPresentation()
        fixture.model.createPIN("1357", confirmation: "1357")

        #expect(fixture.model.state == .unlocked)
        #expect(try fetchSettings(fixture.context).hasParentPIN)

        fixture.model.prepareForPresentation()
        #expect(fixture.model.state == .verify)
        fixture.model.verifyPIN("2468")
        #expect(fixture.model.state == .verify)
        #expect(fixture.model.feedback == .incorrectPIN)

        fixture.model.verifyPIN("1357")
        #expect(fixture.model.state == .unlocked)
    }

    @Test("重置只清凭据和引用并返回创建态")
    func resetClearsOnlyCredentialReference() throws {
        let pin = try ParentPIN("1357")
        let fixture = try makeFixture(storedPIN: pin, settingsHasPIN: true)
        fixture.model.prepareForPresentation()

        fixture.model.resetPIN()

        #expect(fixture.model.state == .setup)
        #expect(fixture.store.storedPIN == nil)
        #expect(try !fetchSettings(fixture.context).hasParentPIN)
    }

    @Test("加载时按实际 Keychain 双向修复非敏感引用")
    func repairsCredentialReferenceBothWays() throws {
        let missingCredential = try makeFixture(settingsHasPIN: true)
        missingCredential.model.prepareForPresentation()
        #expect(try !fetchSettings(missingCredential.context).hasParentPIN)
        #expect(missingCredential.model.state == .setup)

        let existingCredential = try makeFixture(storedPIN: ParentPIN("1357"))
        existingCredential.model.prepareForPresentation()
        #expect(try fetchSettings(existingCredential.context).hasParentPIN)
        #expect(existingCredential.model.state == .verify)
    }

    private func makeFixture(
        storedPIN: ParentPIN? = nil,
        settingsHasPIN: Bool = false
    ) throws -> Fixture {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        context.insert(AppSettings(hasParentPIN: settingsHasPIN))
        try context.save()
        let store = InMemoryParentPINCredentialStore(storedPIN: storedPIN)
        return Fixture(
            container: container,
            context: context,
            store: store,
            model: ParentGateViewModel(context: context, credentialStore: store)
        )
    }

    private func fetchSettings(_ context: ModelContext) throws -> AppSettings {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        return try #require(settings.first)
    }

    private struct Fixture {
        // ModelContext 不负责延长容器生命周期；夹具必须持有容器，避免测试中数据库被提前释放。
        let container: ModelContainer
        let context: ModelContext
        let store: InMemoryParentPINCredentialStore
        let model: ParentGateViewModel
    }
}
