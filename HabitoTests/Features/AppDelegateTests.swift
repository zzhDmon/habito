import Testing
import UIKit
@testable import Habito

@Suite("应用生命周期通知桥")
@MainActor
struct AppDelegateTests {
    @Test("系统显著时间变化回调可到达应用代理")
    func significantTimeChangeCallbackIsRegistered() {
        let delegate = AppDelegate()
        #expect(delegate.responds(to: #selector(UIApplicationDelegate.applicationSignificantTimeChange(_:))))
    }

    @Test("已连接场景的时间变化请求统一重建，不假装排程已经完成")
    func connectedTimeChangeRequestsRebuild() {
        let delegate = AppDelegate()
        let trigger = NotificationRebuildTrigger()
        delegate.connectNotificationRebuildTrigger(trigger)
        #expect(trigger.revision == 0)
        delegate.applicationSignificantTimeChange(.shared)
        #expect(trigger.revision == 1)
        #expect(trigger.state == .idle)
        delegate.applicationSignificantTimeChange(.shared)
        #expect(trigger.revision == 2)
    }

    @Test("启动期多个时间变化合并保存，场景连接后只消费一次")
    func earlyTimeChangesAreConsumedOnceAfterConnection() {
        let delegate = AppDelegate()
        delegate.applicationSignificantTimeChange(.shared)
        delegate.applicationSignificantTimeChange(.shared)
        let trigger = NotificationRebuildTrigger()
        delegate.connectNotificationRebuildTrigger(trigger)
        #expect(trigger.revision == 1)
        delegate.connectNotificationRebuildTrigger(trigger)
        #expect(trigger.revision == 1)
        delegate.applicationSignificantTimeChange(.shared)
        #expect(trigger.revision == 2)
    }
}
