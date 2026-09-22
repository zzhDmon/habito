import Foundation

/// 与 `Calendar.Component.weekday` 一致的星期值；星期日为 1，星期六为 7。
nonisolated enum Weekday: Int, CaseIterable, Hashable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    /// V0 默认上课日规则使用的周一至周五集合。
    static let schoolDays: Set<Weekday> = [
        .monday,
        .tuesday,
        .wednesday,
        .thursday,
        .friday,
    ]
}
