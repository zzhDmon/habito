import Foundation

/// 切换前置条件失败不会改写任何计时事实。
enum TaskTimingSwitchError: Error, Equatable, Sendable {
    case targetUnavailable
    case confirmationRequired
    case runningTasksChanged
}
