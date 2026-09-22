import Foundation
import UserNotifications

/// Habito 关心的本地通知授权状态。
///
/// 该类型隔离系统枚举，避免页面直接依赖 `UserNotifications` 框架的细节。
enum NotificationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    init(systemStatus: UNAuthorizationStatus) {
        switch systemStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }

    /// 当前状态是否允许应用安排系统通知。
    var canSchedule: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied, .unknown:
            false
        }
    }

    /// 面向用户展示的本地化状态名称。
    var title: LocalizedStringResource {
        switch self {
        case .notDetermined:
            .notificationAuthorizationNotDetermined
        case .denied:
            .notificationAuthorizationDenied
        case .authorized:
            .notificationAuthorizationAuthorized
        case .provisional:
            .notificationAuthorizationProvisional
        case .ephemeral:
            .notificationAuthorizationEphemeral
        case .unknown:
            .notificationAuthorizationUnknown
        }
    }
}
