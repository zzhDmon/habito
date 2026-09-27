import Foundation

/// 日期覆盖编排失败的可诊断原因。
enum ParentCalendarDayError: Error, Equatable {
    case historicalDate(LocalDate)
    case duplicateOverride(LocalDate)
    case invalidOverrideType(id: UUID, value: String)
    case missingTemplate(occurrenceID: UUID)
    case invalidOccurrenceStatus(id: UUID, value: String)
}
