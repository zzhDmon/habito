import Foundation

/// 实例核对输入或已有持久化数据不满足业务约束时的错误。
enum OccurrenceReconciliationError: Error, Equatable, Sendable {
    case duplicateCandidateDate(LocalDate)
    case candidateOutsideRange(LocalDate)
    case candidateBeforeToday(LocalDate)
    case candidateRevisionMismatch(candidate: Int, template: Int)
    /// 非有限绝对时刻不能进入实例快照，防止外部手造候选绕过展开器。
    case invalidCandidateTime(date: LocalDate, field: String)
    case inactiveTemplateHasCandidates
    case invalidTemplateConfiguration(templateID: UUID, field: String, rawValue: String)
    case invalidStoredDateKey(occurrenceID: UUID, dateKey: String)
    case invalidStoredStatus(occurrenceID: UUID, rawValue: String)
}
