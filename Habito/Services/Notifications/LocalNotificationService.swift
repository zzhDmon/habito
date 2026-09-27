import Foundation
import UserNotifications

/// 使用 `UNUserNotificationCenter` 实现本地通知授权、排程和取消。
final class LocalNotificationService: LocalNotificationScheduling {
    /// M0 探针始终复用同一个标识，重新安排时会覆盖旧请求，避免测试通知堆积。
    static let probeIdentifier = "habito.notification.probe"

    private let center: UNUserNotificationCenter
    private let now: @Sendable () -> Date

    /// 创建本地通知服务。
    ///
    /// - Parameters:
    ///   - center: 系统通知中心；测试时可替换边界实现而无需直接构造它。
    ///   - now: 当前时间提供者。注入该依赖可避免时间计算绑定真实时钟。
    init(
        center: UNUserNotificationCenter = .current(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.center = center
        self.now = now
    }

    func diagnostics() async -> NotificationDiagnosticSnapshot {
        let settings = await center.notificationSettings()
        return NotificationDiagnosticSnapshot(
            authorization: NotificationAuthorizationState(
                systemStatus: settings.authorizationStatus
            ),
            alerts: NotificationDeliverySettingState(systemSetting: settings.alertSetting),
            sounds: NotificationDeliverySettingState(systemSetting: settings.soundSetting)
        )
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        let currentState = await diagnostics().authorization
        guard currentState == .notDetermined else {
            return currentState
        }

        _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        return await diagnostics().authorization
    }

    func scheduleProbe(
        for scenario: NotificationProbeScenario,
        after delay: TimeInterval
    ) async throws -> Date {
        guard delay >= 1 else {
            throw LocalNotificationServiceError.invalidDelay
        }

        cancelProbe()

        let content = UNMutableNotificationContent()
        content.title = String(localized: .notificationProbeContentTitle)
        content.body = scenario.notificationBody
        content.sound = .default
        content.userInfo = ["probeScenario": scenario.rawValue]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: delay,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.probeIdentifier,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
        return now().addingTimeInterval(delay)
    }

    func pendingProbeDate() async -> Date? {
        let requests = await center.pendingNotificationRequests()
        let probeRequest = requests.first { $0.identifier == Self.probeIdentifier }
        return (probeRequest?.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
    }

    func cancelProbe() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.probeIdentifier])
    }
}
