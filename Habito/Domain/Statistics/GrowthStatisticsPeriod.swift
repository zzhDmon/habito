/// P0 家长统计仅支持已确认的三个日期窗口，不隐含 Streak 或奖励退坡规则。
nonisolated enum GrowthStatisticsPeriod: Int, CaseIterable, Sendable {
    case week = 7
    case fortnight = 14
    case month = 30
}
