/// 固定星期快捷集合；学校放假与补课仍由既有日期覆盖处理，不猜测地区校历。
nonisolated enum TaskWeekdayPreset: String, CaseIterable, Sendable {
    case schoolDays, everyDay, weekend
    var days: Set<Weekday> {
        switch self {
        case .schoolDays: Weekday.schoolDays
        case .everyDay: Set(Weekday.allCases)
        case .weekend: [.saturday, .sunday]
        }
    }
}
