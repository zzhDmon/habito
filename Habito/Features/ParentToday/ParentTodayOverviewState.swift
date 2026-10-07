/// 今日概况失败时没有旧比例；独立于任务管理列表，读取失败不取消已有管理能力。
nonisolated enum ParentTodayOverviewState: Equatable, Sendable {
    case idle
    case loading
    case loaded(GrowthStatisticsDay)
    case failed
}
