import Foundation

/// 用户点击系统通知后，孩子导航栈应采用的安全目标。
nonisolated enum NotificationNavigationDestination: Equatable, Sendable {
    case task(UUID)
    case home
    case ignored
}
