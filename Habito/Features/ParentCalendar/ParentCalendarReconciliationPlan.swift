/// 单个模板在选中日期上的核对计划。
struct ParentCalendarReconciliationPlan {
    let template: TaskTemplate
    let candidates: [ResolvedTaskCandidate]
    let existing: [TaskOccurrence]
}
