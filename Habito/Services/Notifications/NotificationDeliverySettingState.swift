import Foundation
import UserNotifications

/// 系统对提醒展示或声音这类单项通知能力的设置状态。
nonisolated enum NotificationDeliverySettingState: String, Equatable, Sendable {
    case enabled
    case disabled
    case notSupported
    case unknown

    init(systemSetting: UNNotificationSetting) {
        switch systemSetting {
        case .enabled: self = .enabled
        case .disabled: self = .disabled
        case .notSupported: self = .notSupported
        @unknown default: self = .unknown
        }
    }
}
