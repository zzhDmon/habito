import Foundation

/// 今日页面展示所需的不可变完成事实。
struct TodayTaskCompletion: Equatable, Sendable {
    /// 撤销请求捕获完成事件 ID，不能用会再次完成的实例 ID 替代。
    let id: UUID
    let completedAt: Date
    let activeDurationSeconds: TimeInterval
    let source: CompletionSource
}
