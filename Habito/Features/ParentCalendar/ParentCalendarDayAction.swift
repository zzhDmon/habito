/// 家长对选中日期可执行的覆盖操作。
enum ParentCalendarDayAction: Equatable, Sendable {
    case setSchoolDay
    case setHoliday
    case removeOverride

    var dayType: DayType? {
        switch self {
        case .setSchoolDay: .schoolDay
        case .setHoliday: .holiday
        case .removeOverride: nil
        }
    }
}
