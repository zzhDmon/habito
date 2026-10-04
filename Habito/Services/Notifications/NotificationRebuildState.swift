import Foundation

/// 最近一次排程核对的页面状态，不代表系统已实际送达通知。
nonisolated enum NotificationRebuildState: Equatable, Sendable {
    case idle
    case rebuilding
    case completed(NotificationRebuildResult, checkedAt: Date)
    case failed
}
