import Foundation

/// 今日页面使用的只读任务值，不暴露可变的 SwiftData 模型。
struct TodayTaskItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let date: LocalDate
    let scheduledAt: Date
    let title: String
    let iconName: String
    let colorToken: String
    let targetDurationSeconds: TimeInterval
    let status: TaskOccurrenceStatus
    let origin: TaskOccurrenceOrigin
    let activeSessionState: TimerSessionState?
    let activeDurationSeconds: TimeInterval
    let completion: TodayTaskCompletion?
}
