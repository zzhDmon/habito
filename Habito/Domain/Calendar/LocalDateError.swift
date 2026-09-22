import Foundation

/// 创建本地日历日期时可能产生的领域错误。
nonisolated enum LocalDateError: Error, Equatable, Sendable {
    /// 年、月、日无法在指定日历中组成真实日期。
    case invalidComponents(year: Int, month: Int, day: Int)

    /// 持久化日期键不符合 `yyyy-MM-dd`，或它表示的日期不存在。
    case invalidDateKey(String)
}
