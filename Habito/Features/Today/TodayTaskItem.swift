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
    let submission: TaskSubmissionSnapshot?
    let verificationType: TaskVerificationType

    /// 等待是提交事实的派生值，不能另存一个可能与审核历史漂移的状态。
    var isAwaitingReview: Bool { submission?.state == .waiting }

    init(
        id: UUID, date: LocalDate, scheduledAt: Date, title: String, iconName: String, colorToken: String,
        targetDurationSeconds: TimeInterval, status: TaskOccurrenceStatus, origin: TaskOccurrenceOrigin,
        activeSessionState: TimerSessionState?, activeDurationSeconds: TimeInterval, completion: TodayTaskCompletion?,
        submission: TaskSubmissionSnapshot? = nil,
        verificationType: TaskVerificationType = .selfConfirm
    ) {
        self.id = id
        self.date = date
        self.scheduledAt = scheduledAt
        self.title = title
        self.iconName = iconName
        self.colorToken = colorToken
        self.targetDurationSeconds = targetDurationSeconds
        self.status = status
        self.origin = origin
        self.activeSessionState = activeSessionState
        self.activeDurationSeconds = activeDurationSeconds
        self.completion = completion
        self.submission = submission
        self.verificationType = verificationType
    }
}
