import Foundation

/// 计时或完成事务发现不一致数据与非法时间顺序时的错误。
enum TaskProgressServiceError: Error, Equatable, Sendable {
    case invalidOccurrenceStatus(occurrenceID: UUID, rawValue: String)
    case invalidSessionState(sessionID: UUID, rawValue: String)
    case multipleActiveSessions(occurrenceID: UUID)
    case noActiveSession(occurrenceID: UUID)
    case inconsistentOccurrenceAndSessionState(occurrenceID: UUID)
    case negativeAccumulatedDuration(sessionID: UUID)
    case timeBeforeSessionStart(sessionID: UUID)
    case timeBeforeLastResume(sessionID: UUID)
    case timeBeforeSessionEnd(sessionID: UUID)
    case timeBeforeCompletion(occurrenceID: UUID)
    case multipleCompletionRecords(occurrenceID: UUID)
    case completionRecordMissing(occurrenceID: UUID)
    case unexpectedCompletionRecord(occurrenceID: UUID)
}
