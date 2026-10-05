/// V1 任务分类；旧任务有独立的“待设置”值，不被迁移成未经家长选择的分类。
nonisolated enum TaskCategory: String, CaseIterable, Sendable {
    case unassigned
    case basicResponsibility
    case growth
    case challenge
}
