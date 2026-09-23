import Foundation

/// 今日页面展示所需的不可变完成事实。
struct TodayTaskCompletion: Equatable, Sendable {
    let completedAt: Date
    let activeDurationSeconds: TimeInterval
    let source: CompletionSource
}
