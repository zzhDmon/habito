/// 儿童资产的独立只读状态；失败不代表余额为零，也不改变今日任务的可用性。
///
/// 只包含已校验账本派生的有效 XP/Coin，不持有持久化模型或额外成长余额。
nonisolated enum TodayRewardState: Equatable, Sendable {
    case loading
    case loaded(RewardBalance)
    case failed
}
