/// 当地当天已入账且尚未冲正的奖励收入；消费不扣减所得，可用余额另行查询。
nonisolated struct DailyRewardSummary: Equatable, Sendable {
    let earnedXP: Int
    let earnedCoins: Int
}
