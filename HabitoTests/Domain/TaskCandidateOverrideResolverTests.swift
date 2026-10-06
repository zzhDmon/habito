import Foundation
import Testing
@testable import Habito

@Suite("任务候选覆盖规则")
struct TaskCandidateOverrideResolverTests {
    private let resolver = TaskCandidateOverrideResolver()

    @Test("放假覆盖移除普通候选")
    func holidayRemovesGeneratedCandidate() throws {
        let monday = try candidate("2026-09-21", hour: 19)

        let result = try resolver.resolve(
            generated: [monday],
            templateRevision: 3,
            dayOverrides: [.init(date: monday.date, dayType: .holiday)],
            detachedOverrides: []
        )

        #expect(result.isEmpty)
    }

    @Test("撤销放假覆盖后普通候选可由相同输入恢复")
    func removingHolidayRestoresGeneratedCandidate() throws {
        let monday = try candidate("2026-09-21", hour: 19)

        let holidayResult = try resolver.resolve(
            generated: [monday],
            templateRevision: 3,
            dayOverrides: [.init(date: monday.date, dayType: .holiday)],
            detachedOverrides: []
        )
        let restoredResult = try resolver.resolve(
            generated: [monday],
            templateRevision: 3,
            dayOverrides: [],
            detachedOverrides: []
        )

        #expect(holidayResult.isEmpty)
        #expect(restoredResult.map(\.date) == [monday.date])
        #expect(restoredResult.first?.origin == .generated(templateRevision: 3))
    }

    @Test("放假日保留家长明确恢复或新增的单日候选")
    func holidayKeepsDetachedOverride() throws {
        let generated = try candidate("2026-09-21", hour: 19)
        let detached = try candidate("2026-09-21", hour: 10)

        let result = try resolver.resolve(
            generated: [generated],
            templateRevision: 3,
            dayOverrides: [.init(date: generated.date, dayType: .holiday)],
            detachedOverrides: [detached]
        )

        #expect(result.count == 1)
        #expect(result.first?.scheduledAt == detached.scheduledAt)
        #expect(result.first?.origin == .detachedOverride)
    }

    @Test("单日修改只替换当天且不影响后续日期")
    func detachedOverrideOnlyReplacesItsDate() throws {
        let monday = try candidate("2026-09-21", hour: 19)
        let tuesday = try candidate("2026-09-22", hour: 19)
        let changedMonday = try candidate("2026-09-21", hour: 10)

        let result = try resolver.resolve(
            generated: [tuesday, monday],
            templateRevision: 3,
            dayOverrides: [],
            detachedOverrides: [changedMonday]
        )

        #expect(result.map(\.date.dateKey) == ["2026-09-21", "2026-09-22"])
        #expect(result[0].scheduledAt == changedMonday.scheduledAt)
        #expect(result[0].origin == .detachedOverride)
        #expect(result[1].scheduledAt == tuesday.scheduledAt)
        #expect(result[1].origin == .generated(templateRevision: 3))
    }

    @Test("上课日覆盖保留规则已经生成的候选")
    func schoolDayKeepsGeneratedCandidate() throws {
        let saturday = try candidate("2026-09-26", hour: 9)

        let result = try resolver.resolve(
            generated: [saturday],
            templateRevision: 3,
            dayOverrides: [.init(date: saturday.date, dayType: .schoolDay)],
            detachedOverrides: []
        )

        #expect(result.map(\.date) == [saturday.date])
    }

    @Test("重复日期输入会明确失败而不是依赖数组顺序")
    func duplicateInputsAreRejected() throws {
        let candidate = try candidate("2026-09-21", hour: 19)

        #expect(throws: TaskCandidateOverrideError.duplicateGeneratedDate(candidate.date)) {
            try resolver.resolve(
                generated: [candidate, candidate],
                templateRevision: 3,
                dayOverrides: [],
                detachedOverrides: []
            )
        }
        #expect(throws: TaskCandidateOverrideError.duplicateDayOverride(candidate.date)) {
            try resolver.resolve(
                generated: [],
                templateRevision: 3,
                dayOverrides: [
                    .init(date: candidate.date, dayType: .schoolDay),
                    .init(date: candidate.date, dayType: .holiday),
                ],
                detachedOverrides: []
            )
        }
    }

    @Test("覆盖保留来源完整可空时间，单日 nil 不从模板填值", arguments: [false, true])
    func overridesPreserveOptionalSnapshots(clearingDetached: Bool) throws {
        let monday = try candidate("2026-09-21", hour: 19)
        let tuesday = try candidate("2026-09-22", hour: 19)
        let plan = monday.scheduledAt.addingTimeInterval(-600)
        let deadline = monday.scheduledAt.addingTimeInterval(600)
        let generated = ScheduledTaskCandidate(
            date: monday.date, scheduledAt: monday.scheduledAt, plannedAt: plan, deadlineAt: deadline)
        let detached = ScheduledTaskCandidate(
            date: monday.date, scheduledAt: monday.scheduledAt.addingTimeInterval(-3600),
            plannedAt: clearingDetached ? nil : deadline, deadlineAt: clearingDetached ? nil : plan)
        let result = try resolver.resolve(
            generated: [generated, tuesday], templateRevision: 3,
            dayOverrides: [.init(date: monday.date, dayType: .holiday)], detachedOverrides: [detached])
        #expect(result.count == 2)
        #expect(result[0].plannedAt == detached.plannedAt && result[0].deadlineAt == detached.deadlineAt)
        #expect(result[0].origin == .detachedOverride)
        #expect(result[1].plannedAt == nil && result[1].deadlineAt == nil)
        let restored = try #require(
            resolver.resolve(
                generated: [generated], templateRevision: 3, dayOverrides: [], detachedOverrides: []
            ).first)
        #expect(restored.plannedAt == plan && restored.deadlineAt == deadline)
        #expect(restored.origin == .generated(templateRevision: 3))
    }

    private func candidate(_ dateKey: String, hour: Int) throws -> ScheduledTaskCandidate {
        let date = try LocalDate(dateKey: dateKey)
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        return try #require(
            TaskRecurrenceExpander(calendar: .init(identifier: .gregorian), timeZone: timeZone)
                .expand(
                    .once(on: date),
                    timeOfDayMinutes: hour * 60,
                    from: date,
                    through: date
                ).first
        )
    }
}
