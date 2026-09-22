import Testing
@testable import Habito

@Suite("本地通知探针状态")
struct NotificationProbeViewModelTests {
    @Test("授权成功后安排固定两分钟探针")
    func schedulesTwoMinuteProbeAfterAuthorization() async {
        let service = FakeLocalNotificationService()
        let model = NotificationProbeViewModel(notificationService: service)
        model.selectedScenario = .locked

        await model.scheduleProbe()

        #expect(model.authorizationState == .authorized)
        #expect(model.scheduledDate == service.scheduledDate)
        #expect(service.scheduledScenario == .locked)
        #expect(service.scheduledDelay == 120)
    }

    @Test("授权被拒绝时不创建通知请求")
    func doesNotScheduleWhenAuthorizationIsDenied() async {
        let service = FakeLocalNotificationService()
        service.requestedAuthorizationState = .denied
        let model = NotificationProbeViewModel(notificationService: service)

        await model.scheduleProbe()

        #expect(model.authorizationState == .denied)
        #expect(model.scheduledDate == nil)
        #expect(service.scheduledDelay == nil)
    }
}
