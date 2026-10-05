import Foundation
import UserNotifications

/// 使用 `UNUserNotificationCenter` 实现本地通知授权、排程和取消。
final class LocalNotificationService: LocalNotificationScheduling, NotificationRequestScheduling {
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

    func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
        await center.pendingNotificationRequests().map(Self.makePendingNotificationSnapshot)
    }

    /// 把系统挂起请求变成只读快照；旧的浮动时区请求必须在下一次核对时替换。
    ///
    /// - Parameter request: 系统队列返回的请求，不代表通知已经送达。
    /// - Returns: 只有完整公历 UTC 单次触发器才包含可信绝对时间；其他触发器返回空时间，
    ///   由协调器沿用已有替换路径处理。非 Habito 标识仍由协调器隔离，探针不受影响。
    static func makePendingNotificationSnapshot(_ request: UNNotificationRequest) -> PendingNotificationRequestSnapshot
    {
        PendingNotificationRequestSnapshot(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body,
            scheduledAt: absoluteTaskDate(for: request.trigger)
        )
    }

    func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
        try await center.add(Self.makeTaskNotificationRequest(request))
    }

    /// 构造任务系统请求而不访问通知中心，便于固定时间验证边界转换。
    ///
    /// - Parameter request: 业务层已计算好的绝对计划时间与稳定标识。
    /// - Returns: 尚未提交系统的单次通知请求；不会请求权限或改动设备设置。
    /// - Important: 本地重复时刻已由业务层解释为绝对时间；此处用公历 UTC 无歧义编码。
    ///   时区改变后的主提醒仍由统一重建重新计算，不在系统触发器内再次解释业务规则。
    static func makeTaskNotificationRequest(_ request: TaskNotificationRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [
            "occurrenceID": request.occurrenceID.uuidString.lowercased(),
            "notificationKind": request.kind.rawValue,
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: request.scheduledAt)
        // 不传时区会随设备设置重新解释，夏令时回拨的两个同名小时也会丢失绝对时刻区别。
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        return UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
    }

    func removePendingNotificationRequest(identifier: String) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func deliveredNotificationIdentifiers() async throws -> [String] {
        await center.deliveredNotifications().map { $0.request.identifier }
    }

    func removeDeliveredNotificationRequest(identifier: String) async throws {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// 任务只使用完整 UTC 单次日历触发；不能以旧请求当前看似匹配证明它在时区变化后仍正确。
    private static func absoluteTaskDate(for trigger: UNNotificationTrigger?) -> Date? {
        guard let trigger = trigger as? UNCalendarNotificationTrigger, !trigger.repeats else { return nil }
        let components = trigger.dateComponents
        guard
            components.calendar?.identifier == .gregorian,
            components.timeZone == .gmt,
            components.year != nil, components.month != nil, components.day != nil,
            components.hour != nil, components.minute != nil, components.second != nil
        else { return nil }
        // 还原明确绝对时刻，不用 nextTriggerDate 的真实当前时间影响固定测试或挂起队列核对。
        return components.date
    }
}
