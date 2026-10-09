import Foundation

/// 特定日期任务实例的业务状态。
///
/// 暂停只改变 `TimerSessionState`，任务实例仍为 `inProgress`；这样首页可以持续
/// 把暂停中的任务视为“正在做”，而不会与从未开始的 `pending` 混淆。
nonisolated enum TaskOccurrenceStatus: String, CaseIterable, Sendable {
    case pending
    case inProgress
    case completed
    case skipped
    /// 保留唯一键的取消记录，阻止重复规则把已删除的本次任务重新生成。
    case cancelled

    /// 应用一个业务动作并返回新状态，不直接修改持久化对象。
    ///
    /// - Parameter action: 用户或用例层发起的领域动作。
    /// - Returns: 合法转换后的状态。
    /// - Throws: 当前状态不接受该动作时抛出 `DomainStateTransitionError`。
    func applying(_ action: TaskOccurrenceAction) throws -> TaskOccurrenceStatus {
        switch (self, action) {
        case (.pending, .start):
            .inProgress
        case (.pending, .complete), (.inProgress, .complete):
            .completed
        case (.pending, .skip):
            .skipped
        case (.skipped, .restore), (.completed, .undoCompletion):
            .pending
        default:
            throw DomainStateTransitionError(state: rawValue, action: action.rawValue)
        }
    }
}
