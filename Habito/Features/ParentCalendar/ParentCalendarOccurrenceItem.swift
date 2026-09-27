import Foundation

/// 日历页所需的单日任务摘要，不向 View 暴露 SwiftData 模型。
struct ParentCalendarOccurrenceItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let scheduledAt: Date
    let status: TaskOccurrenceStatus
    let isDetachedOverride: Bool
}
