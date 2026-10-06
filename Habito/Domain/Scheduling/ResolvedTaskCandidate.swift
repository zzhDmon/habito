import Foundation

/// 应用日期与单日覆盖后、等待 M1-005 持久化的任务候选。
nonisolated struct ResolvedTaskCandidate: Equatable, Sendable {
    let date: LocalDate
    let scheduledAt: Date
    let origin: TaskOccurrenceOrigin
    let plannedAt: Date?
    let deadlineAt: Date?

    /// 覆盖合并后仍保留来源的完整时间快照，避免后来模板反算单日意图。
    init(
        date: LocalDate, scheduledAt: Date, origin: TaskOccurrenceOrigin,
        plannedAt: Date? = nil, deadlineAt: Date? = nil
    ) {
        self.date = date
        self.scheduledAt = scheduledAt
        self.origin = origin
        self.plannedAt = plannedAt
        self.deadlineAt = deadlineAt
    }
}
