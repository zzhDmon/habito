/// 只读展示组的稳定身份。跨日组不改变任务所属日期、提醒或今日进度。
nonisolated enum TodayTaskGroupKind: Hashable, Sendable {
    case carryOver
    case timePeriod(TaskTimePeriod)

    /// 展示顺序独立于时钟；全天不表示提醒在午夜，跨日也不是新的逾期处罚。
    static let displayOrder: [Self] = [.carryOver] + TaskTimePeriod.allCases.map(Self.timePeriod)
}
