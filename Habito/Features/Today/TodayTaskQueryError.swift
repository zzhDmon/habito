import Foundation

/// 今日查询发现存储数据不满足领域约束时的显式错误。
enum TodayTaskQueryError: Error, Equatable, Sendable {
    case occurrenceNotFound(occurrenceID: UUID)
    case invalidOccurrenceDate(occurrenceID: UUID, value: String)
    case invalidOccurrenceStatus(occurrenceID: UUID, value: String)
    case invalidTargetDuration(occurrenceID: UUID, value: TimeInterval)
    case invalidSessionState(sessionID: UUID, value: String)
    case invalidSessionTimeline(sessionID: UUID)
    case negativeSessionDuration(sessionID: UUID, value: TimeInterval)
    case multipleActiveSessions(occurrenceID: UUID)
    case missingActiveSession(occurrenceID: UUID)
    case unexpectedActiveSession(occurrenceID: UUID)
    case invalidCompletionSource(occurrenceID: UUID, value: String)
    case negativeCompletionDuration(occurrenceID: UUID, value: TimeInterval)
    case multipleCompletionRecords(occurrenceID: UUID)
    case missingCompletionRecord(occurrenceID: UUID)
    case unexpectedCompletionRecord(occurrenceID: UUID)
}
