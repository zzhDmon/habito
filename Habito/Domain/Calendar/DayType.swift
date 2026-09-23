import Foundation

/// 家长为具体日期设置的上课或放假覆盖类型。
nonisolated enum DayType: String, CaseIterable, Sendable {
    case schoolDay
    case holiday
}
