import Foundation

/// M0-004 需要逐项验证的通知运行场景。
enum NotificationProbeScenario: String, CaseIterable, Identifiable, Sendable {
    case foreground
    case background
    case locked
    case terminated

    var id: Self { self }

    /// 场景选择器中的本地化名称。
    var title: LocalizedStringResource {
        switch self {
        case .foreground:
            .notificationProbeScenarioForeground
        case .background:
            .notificationProbeScenarioBackground
        case .locked:
            .notificationProbeScenarioLocked
        case .terminated:
            .notificationProbeScenarioTerminated
        }
    }

    /// 安排通知后需要执行的手工步骤。
    var instruction: LocalizedStringResource {
        switch self {
        case .foreground:
            .notificationProbeInstructionForeground
        case .background:
            .notificationProbeInstructionBackground
        case .locked:
            .notificationProbeInstructionLocked
        case .terminated:
            .notificationProbeInstructionTerminated
        }
    }

    /// 通知正文包含场景名称，便于确认收到的是本轮探针。
    var notificationBody: String {
        switch self {
        case .foreground:
            String(localized: .notificationProbeBodyForeground)
        case .background:
            String(localized: .notificationProbeBodyBackground)
        case .locked:
            String(localized: .notificationProbeBodyLocked)
        case .terminated:
            String(localized: .notificationProbeBodyTerminated)
        }
    }
}
