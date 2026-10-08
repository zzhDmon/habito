/// 与钱包独立的今日所得状态；收入查询失败不等同于今天没有奖励。
nonisolated enum TodayDailyRewardState: Equatable, Sendable {
    case loading
    case loaded(DailyRewardSummary)
    case failed
}
