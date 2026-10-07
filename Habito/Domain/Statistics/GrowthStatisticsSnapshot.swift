/// 完整窗口的纯值结果；可安全传递/比较，不缓存为第二份持久化真相。
nonisolated struct GrowthStatisticsSnapshot: Equatable, Sendable {
    let period: GrowthStatisticsPeriod
    let start: LocalDate
    let end: LocalDate
    let counts: GrowthStatisticsCounts
    let days: [GrowthStatisticsDay]
    let tasks: [GrowthStatisticsTask]
}
