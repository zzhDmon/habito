import Foundation

/// 今日页面展示所需的不可变完成事实。
struct TodayTaskCompletion: Equatable, Sendable {
    /// 撤销请求捕获完成事件 ID，不能用会再次完成的实例 ID 替代。
    let id: UUID
    let completedAt: Date
    let activeDurationSeconds: TimeInterval
    let source: CompletionSource
    /// 保存并经审计验证的提交自主性；旧预览/历史默认unknown，不能由来源推算。
    let timing: CompletionTiming

    init(
        id: UUID, completedAt: Date, activeDurationSeconds: TimeInterval, source: CompletionSource,
        timing: CompletionTiming = .unknown
    ) {
        self.id = id
        self.completedAt = completedAt
        self.activeDurationSeconds = activeDurationSeconds
        self.source = source
        self.timing = timing
    }
}
