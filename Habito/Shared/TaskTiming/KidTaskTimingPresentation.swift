import Foundation

/// 儿童端的纯时间展示值：未设置的时间保持缺席，不以提醒时间偷偷补齐。
///
/// - Important: 截止只影响提示。完成权限和自主奖励仍由原有领域规则判断。
nonisolated struct KidTaskTimingPresentation: Equatable, Sendable {
    let taskID: UUID
    let reminderText: String
    let plannedText: String?
    let deadlineText: String?
    let showsDeadlineHint: Bool
    /// 无截止或等待/完成状态的文案不会随时间变化，不需要为每个任务保持定时刷新。
    let needsDeadlineRefresh: Bool

    /// 页面模型提供业务时刻；同一任务可以在不重新查询数据库的情况下更新截止提示。
    init(task: KidTaskNavigationItem, at now: Date) {
        taskID = task.id
        reminderText = String.localizedStringWithFormat(
            String(localized: "kidTask.reminderTimeText"), task.scheduledTimeText)
        plannedText = task.plannedTimeText.map {
            String.localizedStringWithFormat(String(localized: "kidTask.plannedTimeText"), $0)
        }
        deadlineText = task.deadlineTimeText.map {
            String.localizedStringWithFormat(String(localized: "kidTask.deadlineTimeText"), $0)
        }
        showsDeadlineHint = task.timing.isPastDeadline(at: now)
        needsDeadlineRefresh = task.timing.canShowDeadlineHint && task.timing.deadlineAt != nil
    }

    /// Preview 使用固定时刻与纯值，不读取系统时钟或正式持久化容器。
    static func preview(for task: KidTaskNavigationItem) -> Self {
        Self(task: task, at: Date(timeIntervalSinceReferenceDate: 0))
    }
}
