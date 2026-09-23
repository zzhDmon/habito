import Foundation
import Testing
@testable import Habito

@Suite("任务规则展开器")
struct TaskRecurrenceExpanderTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("一次性规则仅在请求范围包含目标日时生成候选")
    func onceRuleRequiresRequestedDate() throws {
        let recurrence = TaskRecurrence.once(on: try localDate("2026-09-23"))
        let expander = TaskRecurrenceExpander(
            calendar: calendar,
            timeZone: try shanghaiTimeZone()
        )

        let included = try expander.expand(
            recurrence,
            timeOfDayMinutes: 19 * 60 + 30,
            from: localDate("2026-09-20"),
            through: localDate("2026-09-25")
        )
        let excluded = try expander.expand(
            recurrence,
            timeOfDayMinutes: 19 * 60 + 30,
            from: localDate("2026-09-24"),
            through: localDate("2026-09-25")
        )

        #expect(included.map(\.date.dateKey) == ["2026-09-23"])
        #expect(excluded.isEmpty)
        #expect(
            try localTimeComponents(of: included[0].scheduledAt)
                == DateComponents(hour: 19, minute: 30)
        )
    }

    @Test("每周规则可跨越月末且保持日期顺序")
    func weeklyRuleCrossesMonthEnd() throws {
        let recurrence = try TaskRecurrence.weekly(
            on: Set(Weekday.allCases),
            starting: localDate("2026-01-30")
        )

        let candidates = try expander().expand(
            recurrence,
            timeOfDayMinutes: 8 * 60,
            from: localDate("2026-01-30"),
            through: localDate("2026-02-02")
        )

        #expect(
            candidates.map(\.date.dateKey) == [
                "2026-01-30", "2026-01-31", "2026-02-01", "2026-02-02",
            ])
    }

    @Test("每周规则可跨越年末")
    func weeklyRuleCrossesYearEnd() throws {
        let recurrence = try TaskRecurrence.weekly(
            on: Set(Weekday.allCases),
            starting: localDate("2026-12-31")
        )

        let candidates = try expander().expand(
            recurrence,
            timeOfDayMinutes: 8 * 60,
            from: localDate("2026-12-31"),
            through: localDate("2027-01-02")
        )

        #expect(candidates.map(\.date.dateKey) == ["2026-12-31", "2027-01-01", "2027-01-02"])
    }

    @Test("闰年二月包含二十九日")
    func weeklyRuleIncludesLeapDay() throws {
        let recurrence = try TaskRecurrence.weekly(
            on: Set(Weekday.allCases),
            starting: localDate("2028-02-28")
        )

        let candidates = try expander().expand(
            recurrence,
            timeOfDayMinutes: 8 * 60,
            from: localDate("2028-02-28"),
            through: localDate("2028-03-01")
        )

        #expect(candidates.map(\.date.dateKey) == ["2028-02-28", "2028-02-29", "2028-03-01"])
    }

    @Test("星期边界使用注入日历的星期值")
    func weeklyRuleUsesCalendarWeekdayAcrossSundayBoundary() throws {
        let recurrence = try TaskRecurrence.weekly(
            on: [.monday],
            starting: localDate("2026-09-20")
        )

        let candidates = try expander().expand(
            recurrence,
            timeOfDayMinutes: 8 * 60,
            from: localDate("2026-09-20"),
            through: localDate("2026-09-22")
        )

        #expect(candidates.map(\.date.dateKey) == ["2026-09-21"])
    }

    @Test("请求范围与规则有效期取交集")
    func requestedRangeIsClippedToRecurrenceRange() throws {
        let recurrence = try TaskRecurrence.weekly(
            on: Set(Weekday.allCases),
            starting: localDate("2026-09-21"),
            ending: localDate("2026-09-23")
        )

        let candidates = try expander().expand(
            recurrence,
            timeOfDayMinutes: 8 * 60,
            from: localDate("2026-09-19"),
            through: localDate("2026-09-25")
        )

        #expect(candidates.map(\.date.dateKey) == ["2026-09-21", "2026-09-22", "2026-09-23"])
    }

    @Test("相同输入可重复得到完全相同的候选")
    func sameInputProducesStableResult() throws {
        let recurrence = try TaskRecurrence.weekly(
            on: [.monday, .wednesday, .friday],
            starting: localDate("2026-09-01")
        )
        let expander = try expander()

        let first = try expander.expand(
            recurrence,
            timeOfDayMinutes: 19 * 60 + 30,
            from: localDate("2026-09-20"),
            through: localDate("2026-09-30")
        )
        let second = try expander.expand(
            recurrence,
            timeOfDayMinutes: 19 * 60 + 30,
            from: localDate("2026-09-20"),
            through: localDate("2026-09-30")
        )

        #expect(first == second)
    }

    @Test("夏令时缺失时刻在同一天顺延并保留分钟")
    func nonexistentDaylightSavingTimeMovesForward() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let expander = TaskRecurrenceExpander(calendar: calendar, timeZone: losAngeles)
        let date = try localDate("2026-03-08")

        let candidate = try #require(
            expander.expand(
                .once(on: date),
                timeOfDayMinutes: 2 * 60 + 30,
                from: date,
                through: date
            ).first
        )
        var localCalendar = calendar
        localCalendar.timeZone = losAngeles

        #expect(localCalendar.component(.hour, from: candidate.scheduledAt) == 3)
        #expect(localCalendar.component(.minute, from: candidate.scheduledAt) == 30)
        #expect(candidate.date == date)
    }

    @Test("夏令时重复时刻固定选择第一次")
    func repeatedDaylightSavingTimeUsesFirstOccurrence() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let expander = TaskRecurrenceExpander(calendar: calendar, timeZone: losAngeles)
        let date = try localDate("2026-11-01")

        let candidate = try #require(
            expander.expand(
                .once(on: date),
                timeOfDayMinutes: 1 * 60 + 30,
                from: date,
                through: date
            ).first
        )

        // 回拨当天 01:30 出现两次；第一次仍处于 UTC-7 的夏令时阶段。
        #expect(losAngeles.secondsFromGMT(for: candidate.scheduledAt) == -7 * 60 * 60)
        #expect(candidate.date == date)
    }

    @Test("非法分钟数和倒置请求范围会被拒绝")
    func rejectsInvalidInputs() throws {
        let date = try localDate("2026-09-23")
        let laterDate = try localDate("2026-09-24")
        let recurrence = TaskRecurrence.once(on: date)

        #expect(throws: TaskRecurrenceExpansionError.invalidTimeOfDayMinutes(1440)) {
            try expander().expand(
                recurrence,
                timeOfDayMinutes: 1440,
                from: date,
                through: date
            )
        }
        #expect(
            throws: TaskRecurrenceExpansionError.invalidRequestedRange(
                start: laterDate,
                end: date
            )
        ) {
            try expander().expand(
                recurrence,
                timeOfDayMinutes: 8 * 60,
                from: laterDate,
                through: date
            )
        }
    }

    private func expander() throws -> TaskRecurrenceExpander {
        TaskRecurrenceExpander(calendar: calendar, timeZone: try shanghaiTimeZone())
    }

    private func localDate(_ dateKey: String) throws -> LocalDate {
        try LocalDate(dateKey: dateKey)
    }

    private func shanghaiTimeZone() throws -> TimeZone {
        try #require(TimeZone(identifier: "Asia/Shanghai"))
    }

    private func localTimeComponents(of date: Date) throws -> DateComponents {
        var localCalendar = calendar
        localCalendar.timeZone = try shanghaiTimeZone()
        return localCalendar.dateComponents([.hour, .minute], from: date)
    }
}
