import Foundation

/// 任务模板的启用、停用与软删除状态。
///
/// `archived` 是不可逆的软删除终态。归档只阻止未来生成并触发未来实例清理，
/// 不代表删除历史任务实例或完成记录。
nonisolated enum TaskTemplateLifecycleState: String, CaseIterable, Sendable {
    case active
    case disabled
    case archived

    /// 应用生命周期动作并返回新状态。
    ///
    /// - Throws: 重复动作或尝试恢复已归档模板时抛出 `DomainStateTransitionError`。
    func applying(_ action: TaskTemplateLifecycleAction) throws -> TaskTemplateLifecycleState {
        switch (self, action) {
        case (.active, .disable):
            .disabled
        case (.disabled, .enable):
            .active
        case (.active, .archive), (.disabled, .archive):
            .archived
        default:
            throw DomainStateTransitionError(state: rawValue, action: action.rawValue)
        }
    }
}
