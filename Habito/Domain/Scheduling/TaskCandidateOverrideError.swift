/// 候选输入违反“单个模板每天最多一个实例”约束时的错误。
nonisolated enum TaskCandidateOverrideError: Error, Equatable, Sendable {
    case duplicateGeneratedDate(LocalDate)
    case duplicateDetachedDate(LocalDate)
    case duplicateDayOverride(LocalDate)
}
