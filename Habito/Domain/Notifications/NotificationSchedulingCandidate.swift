import Foundation

/// 已物化任务实例对应的主提醒候选，不携带 SwiftData 对象。
nonisolated struct NotificationSchedulingCandidate: Equatable, Sendable {
    let occurrenceID: UUID
    let date: LocalDate
    let scheduledAt: Date
}
