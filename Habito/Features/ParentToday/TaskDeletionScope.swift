/// 家长明确选择的删除范围；周期删除保留已经开始及历史审计。
nonisolated enum TaskDeletionScope: Sendable {
    case occurrence
    case series
}
