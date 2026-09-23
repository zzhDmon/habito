import Foundation

/// 任务重复规则无法展开时的明确错误。
nonisolated enum TaskRecurrenceExpansionError: Error, Equatable, Sendable {
    /// 一天内的分钟数必须落在 0...1439。
    case invalidTimeOfDayMinutes(Int)

    /// 查询范围必须从较早日期指向较晚日期。
    case invalidRequestedRange(start: LocalDate, end: LocalDate)

    /// 注入的日历无法表达给定本地日期。
    case cannotResolveDate(LocalDate)

    /// 注入的日历无法前进到下一个本地日期。
    case cannotAdvanceDate(LocalDate)

    /// 注入的日历或时区无法在当天解析计划时刻。
    case cannotResolveScheduledTime(date: LocalDate, timeOfDayMinutes: Int)
}
