/// 持久化提醒规则无法还原为合法领域规则时的错误。
enum ReminderRuleDecodingError: Error, Equatable, Sendable {
    case unknownScheduleType(String)
    case missingDateKey(field: String)
    case invalidDateKey(field: String, value: String)
    case inconsistentOnceRange
    case unexpectedOneOffDateForWeekly
    case invalidRecurrence(TaskRecurrenceError)
}
