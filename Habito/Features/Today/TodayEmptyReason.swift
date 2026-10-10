/// 今日确实无可见任务时的原因；完成与查询错误继续由原页面状态表达。
enum TodayEmptyReason: Equatable, Sendable {
    case firstSetup
    case restDay
    case holiday
}
