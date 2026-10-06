import Foundation

/// 规则展开后得到的单日任务候选。
///
/// `date` 用于后续生成稳定的本地日期键，`scheduledAt` 则是结合业务日历与时区后
/// 得到的提醒绝对时刻。计划/截止独立可空，不从提醒推断。此类型不包含持久化身份。
nonisolated struct ScheduledTaskCandidate: Equatable, Sendable {
    let date: LocalDate
    let scheduledAt: Date
    let plannedAt: Date?
    let deadlineAt: Date?

    /// 可空值默认为 nil，以保持旧提醒规则调用兼容；nil 代表未设置，不是使用提醒时间。
    init(date: LocalDate, scheduledAt: Date, plannedAt: Date? = nil, deadlineAt: Date? = nil) {
        self.date = date
        self.scheduledAt = scheduledAt
        self.plannedAt = plannedAt
        self.deadlineAt = deadlineAt
    }
}
