/// 主提醒预算选择结果和可展示的覆盖边界。
nonisolated struct NotificationCandidateSelection: Equatable, Sendable {
    let primaryCandidates: [NotificationSchedulingCandidate]
    let coverageThrough: LocalDate
    let isCoverageBoundaryPartial: Bool
    let hasMinimumCoverage: Bool
}
