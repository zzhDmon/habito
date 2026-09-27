import SwiftData
import Testing
@testable import Habito

@Suite("通知权限协调")
@MainActor
struct NotificationPermissionServiceTests {
    @Test("首次未决定时请求一次并持久化最终授权")
    func requestsOnceAndPersistsFinalAuthorization() async throws {
        let fixture = try makeFixture()
        fixture.provider.currentAuthorizationState = .notDetermined
        fixture.provider.requestedAuthorizationState = .authorized

        let snapshot = try await fixture.service.requestIfNeeded()

        #expect(fixture.provider.requestCount == 1)
        #expect(snapshot.authorization == .authorized)
        #expect(try fetchSettings(fixture.context).lastNotificationAuthorization == .authorized)
    }

    @Test("已经拒绝时不重复弹窗且任务流程可继续读取状态")
    func deniedDoesNotRequestAgain() async throws {
        let fixture = try makeFixture()
        fixture.provider.currentAuthorizationState = .denied
        fixture.provider.alertSetting = .disabled
        fixture.provider.soundSetting = .disabled

        let snapshot = try await fixture.service.requestIfNeeded()

        #expect(fixture.provider.requestCount == 0)
        #expect(!snapshot.canPresentAlerts)
        #expect(try fetchSettings(fixture.context).lastNotificationAuthorization == .denied)
    }

    @Test("提醒与声音分别诊断，不能由总授权推断")
    func distinguishesAlertAndSoundSettings() async throws {
        let fixture = try makeFixture()
        fixture.provider.currentAuthorizationState = .authorized
        fixture.provider.alertSetting = .enabled
        fixture.provider.soundSetting = .disabled

        let snapshot = try await fixture.service.refresh()

        #expect(snapshot.canPresentAlerts)
        #expect(!snapshot.canPlaySounds)
    }

    private func makeFixture() throws -> Fixture {
        let container = try AppModelContainer.make(inMemory: true)
        let provider = FakeLocalNotificationService()
        return Fixture(
            container: container,
            context: container.mainContext,
            provider: provider,
            service: NotificationPermissionService(
                context: container.mainContext,
                provider: provider
            )
        )
    }

    private func fetchSettings(_ context: ModelContext) throws -> AppSettings {
        try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
    }

    private struct Fixture {
        // ModelContext 不延长容器生命周期，测试夹具必须持有容器。
        let container: ModelContainer
        let context: ModelContext
        let provider: FakeLocalNotificationService
        let service: NotificationPermissionService
    }
}
