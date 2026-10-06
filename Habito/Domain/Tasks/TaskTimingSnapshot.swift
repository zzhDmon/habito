import Foundation

/// 儿童首页与执行页共用的只读计划/截止快照，不是新的持久化任务状态。
///
/// 提醒仍由原 scheduledAt 表达；这里不从提醒补计划或截止，也不控制完成、通知或奖励。
/// 可提示资格由查询的任务/提交事实一次派生，避免不同页面各自猜测 waiting。
nonisolated struct TaskTimingSnapshot: Hashable, Sendable {
    static let unspecified = TaskTimingSnapshot(plannedAt: nil, deadlineAt: nil, canShowDeadlineHint: false)

    let plannedAt: Date?
    let deadlineAt: Date?
    let canShowDeadlineHint: Bool

    /// 以调用方注入时刻判断是否超过截止，相等时还未超过。
    ///
    /// - Parameter now: 业务时间环境提供的绝对时刻；不能在规则中直接读系统时钟。
    /// - Returns: 仅可执行且已有截止的任务严格过点时返回 true；不会改变完成权限。
    /// - Important: 生产快照由查询校验有限时刻。额外有限检查保护手造 Preview/测试值，
    ///   不替代持久化错误反馈；等待/完成/跳过的资格在查询层设为 false。
    func isPastDeadline(at now: Date) -> Bool {
        guard canShowDeadlineHint, let deadlineAt,
            now.timeIntervalSinceReferenceDate.isFinite,
            deadlineAt.timeIntervalSinceReferenceDate.isFinite
        else { return false }
        return now > deadlineAt
    }
}
