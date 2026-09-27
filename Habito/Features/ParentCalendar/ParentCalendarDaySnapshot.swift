/// 家长日历页的一次不可变读取结果。
struct ParentCalendarDaySnapshot: Equatable, Sendable {
    let date: LocalDate
    let naturalDayType: DayType
    let overrideDayType: DayType?
    let isHistorical: Bool
    let occurrences: [ParentCalendarOccurrenceItem]
}
