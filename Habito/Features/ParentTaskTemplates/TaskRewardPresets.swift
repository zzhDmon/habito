/// 产品调校的可选档位，不是自动奖励规则；手输值仍使用既有严格校验。
nonisolated enum TaskRewardPresets {
    static let xp = [0, 5, 10, 15, 20]
    static let coins = [0, 1, 2, 3, 5]
    static let autonomyCoins = [0, 1, 2]
}
