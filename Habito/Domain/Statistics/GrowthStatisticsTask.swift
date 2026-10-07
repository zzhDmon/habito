import Foundation

/// 按稳定模板 ID 聚合；历史改名不拆成两条趋势，标题只取窗口内最新实例快照。
nonisolated struct GrowthStatisticsTask: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let counts: GrowthStatisticsCounts
    let days: [GrowthStatisticsDay]
}
