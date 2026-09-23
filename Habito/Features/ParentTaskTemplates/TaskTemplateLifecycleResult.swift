/// 模板生命周期事务的结果，保留预览快照与实际实例核对报告用于 UI 刷新和诊断。
struct TaskTemplateLifecycleResult: Equatable, Sendable {
    let impact: TaskTemplateLifecycleImpact
    let reconciliationReport: OccurrenceReconciliationReport?
}
