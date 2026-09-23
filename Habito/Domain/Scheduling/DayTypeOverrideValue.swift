/// 从持久化模型读取后供纯领域规则使用的日期类型覆盖值。
nonisolated struct DayTypeOverrideValue: Equatable, Sendable {
    let date: LocalDate
    let dayType: DayType
}
