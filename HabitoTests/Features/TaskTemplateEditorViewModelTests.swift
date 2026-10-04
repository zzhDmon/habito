import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("任务编辑器通知权限接入")
@MainActor
struct TaskTemplateEditorViewModelTests {
    @Test("首次保存等待用户授权返回后再次重建，不依赖通知弹窗切换前后台")
    func firstAuthorizationResponseRequestsFreshRebuild() async throws {
        let fixture = try makeFixture()
        fixture.model.load()
        fixture.model.draft.title = "首次提醒"
        var revisionWhileAwaiting: Int?
        fixture.provider.onRequestAuthorization = {
            revisionWhileAwaiting = fixture.rebuildTrigger.revision
            let templateCount = try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>())
            #expect(templateCount == 1)
            #expect(fixture.provider.currentAuthorizationState == .notDetermined)
        }
        let outcome = await fixture.model.save()
        #expect(outcome == .saved)
        #expect(revisionWhileAwaiting == 1)
        #expect(fixture.provider.currentAuthorizationState == .authorized)
        #expect(fixture.rebuildTrigger.revision == 2)
    }

    @Test("权限已拒绝仍保存任务且不重复请求")
    func deniedPermissionDoesNotBlockSave() async throws {
        let fixture = try makeFixture()
        fixture.provider.currentAuthorizationState = .denied
        fixture.model.load()
        fixture.model.draft.title = "阅读"

        let outcome = await fixture.model.save()

        #expect(outcome == .saved)
        #expect(fixture.provider.requestCount == 0)
        #expect(fixture.rebuildTrigger.revision == 2)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    }

    @Test("系统权限调用失败时任务保留并返回可见警告")
    func permissionFailureKeepsSavedTask() async throws {
        let fixture = try makeFixture()
        fixture.provider.requestError = NSError(domain: "NotificationPermissionTest", code: 1)
        fixture.model.load()
        fixture.model.draft.title = "写字"

        let outcome = await fixture.model.save()

        #expect(outcome == .savedWithNotificationWarning)
        #expect(fixture.rebuildTrigger.revision == 2)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    }

    private func makeFixture() throws -> Fixture {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let provider = FakeLocalNotificationService()
        let rebuildTrigger = NotificationRebuildTrigger()
        let model = TaskTemplateEditorViewModel(
            templateID: nil,
            service: TaskTemplateEditingService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            ),
            lifecycleService: TaskTemplateLifecycleService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            ),
            notificationPermissionService: NotificationPermissionService(
                context: context,
                provider: provider
            ),
            notificationRebuildTrigger: rebuildTrigger,
            dateProvider: FixedDateProvider(value: Date(timeIntervalSince1970: 1_800_000_000)),
            calendar: calendar,
            timeZone: timeZone
        )
        return Fixture(
            container: container,
            context: context,
            provider: provider,
            rebuildTrigger: rebuildTrigger,
            model: model
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let provider: FakeLocalNotificationService
        let rebuildTrigger: NotificationRebuildTrigger
        let model: TaskTemplateEditorViewModel
    }
}
