import Foundation

/// 创建 V0 重复规则时的校验错误。
nonisolated enum TaskRecurrenceError: Error, Equatable, Sendable {
    /// 每周规则至少需要选择一天。
    case emptyWeekdays

    /// 可选结束日期不能早于开始日期。
    case endDateBeforeStartDate
}
