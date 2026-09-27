import Foundation

/// 写入日期覆盖前向家长展示的可审阅影响。
struct ParentCalendarDayImpact: Equatable, Identifiable, Sendable {
    let id = UUID()
    let date: LocalDate
    let action: ParentCalendarDayAction
    let insertedCount: Int
    let deletedCount: Int
    let protectedCount: Int
}
