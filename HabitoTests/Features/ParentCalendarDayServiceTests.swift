import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("家长日期覆盖与实例重建")
@MainActor
struct ParentCalendarDayServiceTests {
    @Test("放假预览和执行只移除普通待处理实例")
    func holidayRemovesOnlyMutableOccurrence() throws {
        let fixture = try Fixture()
        let pending = try fixture.insertTemplateAndOccurrence(status: .pending)
        let detached = try fixture.insertTemplateAndOccurrence(status: .pending, detached: true)
        let skipped = try fixture.insertTemplateAndOccurrence(status: .skipped)

        let impact = try fixture.service.preview(
            .setHoliday,
            on: fixture.date,
            today: fixture.date
        )
        #expect(impact.insertedCount == 0)
        #expect(impact.deletedCount == 1)
        #expect(impact.protectedCount == 2)

        let report = try fixture.service.apply(
            .setHoliday,
            on: fixture.date,
            today: fixture.date,
            now: fixture.now
        )
        let remaining = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())

        #expect(report.deletedCount == 1)
        #expect(report.protectedCount == 2)
        #expect(!remaining.contains { $0.id == pending.id })
        #expect(remaining.contains { $0.id == detached.id })
        #expect(remaining.contains { $0.id == skipped.id })
        #expect(try fixture.overrideType() == .holiday)
    }

    @Test("日期覆盖成功后请求重建通知")
    func viewModelRequestsNotificationRebuildAfterOverride() throws {
        let fixture = try Fixture()
        _ = try fixture.insertTemplateAndOccurrence(status: .pending)
        let trigger = NotificationRebuildTrigger()
        let model = ParentCalendarDayViewModel(
            context: fixture.context,
            calendar: Calendar(identifier: .gregorian),
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now),
            notificationRebuildTrigger: trigger
        )
        model.selectedDate = try Date("2026-09-25T04:00:00Z", strategy: .iso8601)

        model.preview(.setHoliday)
        model.confirmPendingAction()

        #expect(trigger.revision == 1)
        #expect(try fixture.overrideType() == .holiday)
    }

    @Test("撤销放假后按模板恢复且重复执行不产生重复实例")
    func removingHolidayRestoresTemplateOccurrenceIdempotently() throws {
        let fixture = try Fixture()
        _ = try fixture.insertTemplateAndOccurrence(status: .pending)
        _ = try fixture.service.apply(
            .setHoliday,
            on: fixture.date,
            today: fixture.date,
            now: fixture.now
        )

        let impact = try fixture.service.preview(
            .removeOverride,
            on: fixture.date,
            today: fixture.date
        )
        #expect(impact.insertedCount == 1)
        #expect(impact.deletedCount == 0)

        let first = try fixture.service.apply(
            .removeOverride,
            on: fixture.date,
            today: fixture.date,
            now: fixture.now
        )
        let second = try fixture.service.apply(
            .removeOverride,
            on: fixture.date,
            today: fixture.date,
            now: fixture.now
        )

        #expect(first.insertedCount == 1)
        #expect(second == .init(insertedCount: 0, updatedCount: 0, deletedCount: 0, protectedCount: 0))
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
        #expect(try fixture.overrideType() == nil)
    }

    @Test("周末标记上课不会扩张模板原有星期规则")
    func schoolDayDoesNotExpandTemplateWeekdays() throws {
        let fixture = try Fixture(dateKey: "2026-09-26")
        _ = try fixture.insertTemplate(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])

        let report = try fixture.service.apply(
            .setSchoolDay,
            on: fixture.date,
            today: fixture.date,
            now: fixture.now
        )
        let snapshot = try fixture.service.snapshot(for: fixture.date, today: fixture.date)

        #expect(report.insertedCount == 0)
        #expect(snapshot.naturalDayType == .holiday)
        #expect(snapshot.overrideDayType == .schoolDay)
        #expect(snapshot.occurrences.isEmpty)
    }

    @Test("历史日期可查看但不允许预览或写入覆盖")
    func historyIsReadOnly() throws {
        let fixture = try Fixture(dateKey: "2026-09-22")
        let today = try LocalDate(dateKey: "2026-09-23")
        let snapshot = try fixture.service.snapshot(for: fixture.date, today: today)

        #expect(snapshot.isHistorical)
        #expect(throws: ParentCalendarDayError.historicalDate(fixture.date)) {
            try fixture.service.preview(.setHoliday, on: fixture.date, today: today)
        }
        #expect(throws: ParentCalendarDayError.historicalDate(fixture.date)) {
            try fixture.service.apply(
                .setHoliday,
                on: fixture.date,
                today: today,
                now: fixture.now
            )
        }
    }

    @Test("撤销放假恢复两个可空时间且五次核对稳定", arguments: [false, true])
    func restoredHolidayPropagatesOptionalTimes(onlyDeadline: Bool) throws {
        let fixture = try Fixture()
        fixture.context.autosaveEnabled = false
        let template = try fixture.insertTemplate(weekdays: Set(Weekday.allCases))
        let rule = try #require(template.reminderRule)
        rule.plannedTimeOfDayMinutes = onlyDeadline ? nil : 8 * 60
        rule.deadlineTimeOfDayMinutes = 22 * 60
        try fixture.context.save()
        _ = try fixture.service.apply(.setHoliday, on: fixture.date, today: fixture.date, now: fixture.now)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        var id: UUID?
        for iteration in 0..<5 {
            let report = try fixture.service.apply(
                .removeOverride, on: fixture.date, today: fixture.date, now: fixture.now)
            let row = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            if iteration == 0 { id = row.id }
            #expect(row.id == id && report.insertedCount == (iteration == 0 ? 1 : 0) && report.updatedCount == 0)
            #expect(row.plannedAt == (onlyDeadline ? nil : try Date("2026-09-25T00:00:00Z", strategy: .iso8601)))
            #expect(row.deadlineAt == (try Date("2026-09-25T14:00:00Z", strategy: .iso8601)))
            #expect(row.scheduledAt == (try Date("2026-09-25T11:00:00Z", strategy: .iso8601)))
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }

    @Test("日期覆盖保留单日可空时间，不用模板回填")
    func calendarPreservesDetachedOptionalSnapshots() throws {
        let fixture = try Fixture()
        let row = try fixture.insertTemplateAndOccurrence(status: .pending, detached: true)
        let rule = try #require(row.template?.reminderRule)
        rule.plannedTimeOfDayMinutes = 8 * 60
        rule.deadlineTimeOfDayMinutes = 22 * 60
        row.plannedAt = nil
        row.deadlineAt = fixture.now
        try fixture.context.save()
        let report = try fixture.service.apply(.setHoliday, on: fixture.date, today: fixture.date, now: fixture.now)
        #expect(report.protectedCount == 1 && row.plannedAt == nil && row.deadlineAt == fixture.now)
    }

    private final class Fixture {
        let context: ModelContext
        let service: ParentCalendarDayService
        let date: LocalDate
        let now: Date
        let timeZone: TimeZone

        init(dateKey: String = "2026-09-25") throws {
            context = ModelContext(try AppModelContainer.make(inMemory: true))
            date = try LocalDate(dateKey: dateKey)
            now = try Date("2026-09-24T03:00:00Z", strategy: .iso8601)
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            service = ParentCalendarDayService(
                context: context,
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
        }

        func insertTemplateAndOccurrence(
            status: TaskOccurrenceStatus,
            detached: Bool = false
        ) throws -> TaskOccurrence {
            let template = try insertTemplate(weekdays: Set(Weekday.allCases))
            let scheduledAt = try #require(
                TaskRecurrenceExpander(calendar: .init(identifier: .gregorian), timeZone: timeZone)
                    .expand(
                        .once(on: date),
                        timeOfDayMinutes: 19 * 60,
                        from: date,
                        through: date
                    ).first?.scheduledAt
            )
            let occurrence = TaskOccurrence(
                templateID: template.id,
                date: date,
                scheduledAt: scheduledAt,
                titleSnapshot: template.title,
                iconSnapshot: template.iconName,
                colorSnapshot: template.colorToken,
                targetDurationSnapshot: template.targetDurationSeconds,
                status: status,
                sourceRevision: template.revision,
                isDetachedOverride: detached,
                createdAt: now,
                updatedAt: now
            )
            occurrence.template = template
            context.insert(occurrence)
            try context.save()
            return occurrence
        }

        func insertTemplate(weekdays: Set<Weekday>) throws -> TaskTemplate {
            let template = TaskTemplate(
                title: "阅读",
                iconName: "book.fill",
                colorToken: "reading",
                targetDurationSeconds: 900,
                createdAt: now,
                updatedAt: now
            )
            let rule = ReminderRule(
                taskTemplateID: template.id,
                recurrence: try .weekly(on: weekdays, starting: date),
                timeOfDayMinutes: 19 * 60
            )
            context.insert(template)
            context.insert(rule)
            template.reminderRule = rule
            rule.taskTemplate = template
            try context.save()
            return template
        }

        func overrideType() throws -> DayType? {
            try context.fetch(FetchDescriptor<DayOverride>()).first?.dayType
        }
    }
}
