import Foundation
import Observation
import OSLog

/// 本地通知探针页面的可观察状态和用户意图处理。
///
/// 该类型不直接访问 `UNUserNotificationCenter`，系统行为统一经由
/// `LocalNotificationScheduling` 注入，便于测试授权拒绝和排程结果。
@Observable
final class NotificationProbeViewModel {
    /// M0-004 明确要求使用两分钟延迟，避免实现与手工验收标准产生偏差。
    static let probeDelay: TimeInterval = 120

    var selectedScenario: NotificationProbeScenario = .foreground

    private(set) var authorizationState: NotificationAuthorizationState = .unknown
    private(set) var scheduledDate: Date?
    private(set) var statusMessage: LocalizedStringResource = .notificationProbeStatusReady
    private(set) var isWorking = false

    private let notificationService: any LocalNotificationScheduling
    private let logger = Logger(
        subsystem: "com.zhangzehua.Habito",
        category: "NotificationProbe"
    )

    init(notificationService: any LocalNotificationScheduling) {
        self.notificationService = notificationService
    }

    /// 刷新授权和系统待处理请求，支持 App 被终止后恢复探针状态。
    func refresh() async {
        authorizationState = await notificationService.diagnostics().authorization
        scheduledDate = await notificationService.pendingProbeDate()
        statusMessage =
            scheduledDate == nil
            ? .notificationProbeStatusReady
            : .notificationProbeStatusScheduled
    }

    /// 请求权限并安排两分钟后的测试通知。
    func scheduleProbe() async {
        guard !isWorking else { return }

        isWorking = true
        statusMessage = .notificationProbeStatusRequesting
        defer { isWorking = false }

        do {
            authorizationState = try await notificationService.requestAuthorization()
            guard authorizationState.canSchedule else {
                scheduledDate = nil
                statusMessage = .notificationProbeStatusDenied
                return
            }

            scheduledDate = try await notificationService.scheduleProbe(
                for: selectedScenario,
                after: Self.probeDelay
            )
            statusMessage = .notificationProbeStatusScheduled
        } catch {
            scheduledDate = nil
            statusMessage = .notificationProbeStatusFailed
            logger.error("安排本地通知失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 取消当前唯一的待触发探针通知。
    func cancelProbe() {
        notificationService.cancelProbe()
        scheduledDate = nil
        statusMessage = .notificationProbeStatusCancelled
    }
}
