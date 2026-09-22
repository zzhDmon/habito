import Testing
@testable import Habito

@Suite("任务重复规则")
struct TaskRecurrenceTests {
    @Test("一次性规则只保存目标日期")
    func onceRuleUsesOnlyTargetDate() throws {
        let date = try LocalDate(dateKey: "2026-09-22")
        let recurrence = TaskRecurrence.once(on: date)

        #expect(recurrence.kind == .once)
        #expect(recurrence.oneOffDate == date)
        #expect(recurrence.startDate == date)
        #expect(recurrence.endDate == date)
        #expect(recurrence.weekdays.isEmpty)
    }

    @Test("每周规则保存星期和有效日期范围")
    func weeklyRuleUsesSelectedWeekdaysAndRange() throws {
        let start = try LocalDate(dateKey: "2026-09-01")
        let end = try LocalDate(dateKey: "2026-12-31")
        let recurrence = try TaskRecurrence.weekly(
            on: [.monday, .wednesday, .friday],
            starting: start,
            ending: end
        )

        #expect(recurrence.kind == .weekly)
        #expect(recurrence.weekdays == [.monday, .wednesday, .friday])
        #expect(recurrence.oneOffDate == nil)
        #expect(recurrence.startDate == start)
        #expect(recurrence.endDate == end)
    }

    @Test("每周规则不能没有重复日")
    func weeklyRuleRejectsEmptyWeekdays() throws {
        let start = try LocalDate(dateKey: "2026-09-01")

        #expect(throws: TaskRecurrenceError.emptyWeekdays) {
            try TaskRecurrence.weekly(on: [], starting: start)
        }
    }

    @Test("每周规则结束日期不能早于开始日期")
    func weeklyRuleRejectsReversedRange() throws {
        let start = try LocalDate(dateKey: "2026-09-22")
        let end = try LocalDate(dateKey: "2026-09-21")

        #expect(throws: TaskRecurrenceError.endDateBeforeStartDate) {
            try TaskRecurrence.weekly(on: [.tuesday], starting: start, ending: end)
        }
    }
}
