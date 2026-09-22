import Foundation

/// 会改变任务实例状态的领域动作。
nonisolated enum TaskOccurrenceAction: String, CaseIterable, Sendable {
    case start
    case complete
    case skip
    case restore
    case undoCompletion
}
