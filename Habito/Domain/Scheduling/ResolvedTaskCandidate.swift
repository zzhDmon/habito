import Foundation

/// 应用日期与单日覆盖后、等待 M1-005 持久化的任务候选。
nonisolated struct ResolvedTaskCandidate: Equatable, Sendable {
    let date: LocalDate
    let scheduledAt: Date
    let origin: TaskOccurrenceOrigin
}
