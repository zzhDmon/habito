import Foundation

/// 任务执行页的稍后提醒反馈；业务错误映射为孩子可以理解的有限状态。
enum TaskSnoozeState: Equatable, Sendable {
    case idle
    case scheduling
    case scheduled(Date)
    case crossesMidnight
    case budgetFull
    case unavailable
    case failed
}
