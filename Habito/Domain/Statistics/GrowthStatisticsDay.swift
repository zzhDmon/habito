/// 每个日期标签都保留；无实例日的比率为空，不补造“当天本应完成”的任务。
nonisolated struct GrowthStatisticsDay: Equatable, Sendable, Identifiable {
    let date: LocalDate
    let counts: GrowthStatisticsCounts
    var id: String { date.dateKey }
}
