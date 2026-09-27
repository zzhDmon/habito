import Foundation

/// Habito 期望交给系统的一条任务通知，不携带 SwiftData 或系统框架对象。
nonisolated struct TaskNotificationRequest: Equatable, Sendable {
    let occurrenceID: UUID
    let kind: NotificationKind
    let title: String
    let body: String
    let scheduledAt: Date

    var identifier: String {
        NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: kind).rawValue
    }
}
