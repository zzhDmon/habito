import Foundation

/// 家长改单日实例时可能遇到的业务错误。
nonisolated enum ParentTodayTaskManagementError: Error, Equatable, Sendable {
    case occurrenceNotFound(occurrenceID: UUID)
    case invalidOccurrenceDate(occurrenceID: UUID, value: String)
    case invalidOccurrenceStatus(occurrenceID: UUID, value: String)
    case scheduledTimeOutsideOccurrenceDate(occurrenceID: UUID)
    case actionUnavailable(occurrenceID: UUID, status: TaskOccurrenceStatus)
    case inProgressCannotBeCorrected(occurrenceID: UUID)
}
