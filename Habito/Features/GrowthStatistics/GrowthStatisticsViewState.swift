/// 未进入PIN后页面时保持idle；失败状态不携带陈旧比例。
nonisolated enum GrowthStatisticsViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded(GrowthStatisticsSnapshot)
    case failed
}
