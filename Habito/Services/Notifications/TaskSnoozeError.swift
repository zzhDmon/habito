import Foundation

/// 创建稍后提醒时可由孩子界面明确解释的业务错误。
nonisolated enum TaskSnoozeError: Error, Equatable, Sendable {
    case occurrenceNotFound(UUID)
    case invalidOccurrenceStatus(UUID, String)
    case invalidOccurrenceDate(UUID, String)
    case occurrenceIsNotToday(UUID)
    case crossesLocalMidnight
    case pendingLimitReached(Int)
    case notificationsUnavailable
    case submissionChanged(UUID)
}
