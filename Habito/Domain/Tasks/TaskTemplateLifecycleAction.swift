import Foundation

/// 改变任务模板生命周期的领域动作。
nonisolated enum TaskTemplateLifecycleAction: String, CaseIterable, Sendable {
    case disable
    case enable
    case archive
}
