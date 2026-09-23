import Foundation

/// 不携带时区和具体时刻的本地日历日期。
///
/// Habito 使用它表达“2026 年 9 月 22 日这一天”，避免把午夜 `Date`
/// 错当成可跨时区保持不变的日期。只有在安排实例或通知时，才结合注入的
/// `Calendar` 和 `TimeZone` 转换为绝对时间。
nonisolated struct LocalDate: Equatable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    /// 使用公历校验并创建本地日期。
    ///
    /// - Throws: 当年月日无法组成真实公历日期时抛出 `LocalDateError.invalidComponents`。
    init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year) else {
            throw LocalDateError.invalidComponents(year: year, month: month, day: day)
        }

        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        )

        guard
            let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day], from: date)
                == DateComponents(year: year, month: month, day: day)
        else {
            throw LocalDateError.invalidComponents(year: year, month: month, day: day)
        }

        self.year = year
        self.month = month
        self.day = day
    }

    /// 从绝对时间提取指定日历及时区中的本地日期。
    ///
    /// - Parameters:
    ///   - date: 需要解释的绝对时间。
    ///   - calendar: 业务当前使用的日历。调用方必须显式注入，测试不可依赖设备默认值。
    ///   - timeZone: 用于解释 `date` 的时区。
    /// - Throws: 日历无法产生完整年月日时抛出 `LocalDateError.invalidComponents`。
    init(date: Date, calendar: Calendar, timeZone: TimeZone) throws {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let components = localCalendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year, let month = components.month, let day = components.day else {
            throw LocalDateError.invalidComponents(year: 0, month: 0, day: 0)
        }

        self.year = year
        self.month = month
        self.day = day
    }

    /// 从持久化使用的固定日期键创建本地日期。
    ///
    /// - Parameter dateKey: 严格的 `yyyy-MM-dd` 字符串。
    /// - Throws: 格式错误或日期不存在时抛出 `LocalDateError.invalidDateKey`。
    init(dateKey: String) throws {
        let parts = dateKey.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].count == 4,
            parts[1].count == 2,
            parts[2].count == 2,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            throw LocalDateError.invalidDateKey(dateKey)
        }

        do {
            try self.init(year: year, month: month, day: day)
        } catch {
            throw LocalDateError.invalidDateKey(dateKey)
        }
    }

    /// 持久化和唯一性判断使用的稳定日期键。
    var dateKey: String {
        [
            Self.zeroPadded(year, width: 4),
            Self.zeroPadded(month, width: 2),
            Self.zeroPadded(day, width: 2),
        ].joined(separator: "-")
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    private static func zeroPadded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
