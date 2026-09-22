import Foundation

/// 可恢复计时会话的持久化状态。
nonisolated enum TimerSessionState: String, CaseIterable, Sendable {
    case running
    case paused
    case ended

    /// 应用计时动作并返回新状态。
    ///
    /// - Important: `ended` 是终态。完成撤销只影响任务与完成记录，不能复活旧计时会话。
    /// - Throws: 当前状态不接受该动作时抛出 `DomainStateTransitionError`。
    func applying(_ action: TimerSessionAction) throws -> TimerSessionState {
        switch (self, action) {
        case (.running, .pause):
            .paused
        case (.paused, .resume):
            .running
        case (.running, .end), (.paused, .end):
            .ended
        default:
            throw DomainStateTransitionError(state: rawValue, action: action.rawValue)
        }
    }
}
