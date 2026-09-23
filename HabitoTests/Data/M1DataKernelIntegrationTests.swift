import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("M1 数据内核磁盘闭环")
struct M1DataKernelIntegrationTests {
    @Test("规则覆盖实例计时完成和模板修订可跨重开保持一致")
    func fullKernelFlowSurvivesReopen() throws {
        let directory = URL.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Habito-M1.store")
        let templateID = UUID()

        try seedAndComplete(storeURL: storeURL, templateID: templateID)
        try reviseTemplateAfterReopen(storeURL: storeURL, templateID: templateID)
        try verifyFinalStore(storeURL: storeURL, templateID: templateID)
    }

    @Test("损坏的持久化规则不会被静默解释")
    func corruptedReminderRuleIsRejected() throws {
        let date = try localDate("2026-09-21")
        let rule = ReminderRule(
            taskTemplateID: UUID(),
            recurrence: .once(on: date),
            timeOfDayMinutes: 19 * 60 + 30
        )

        rule.scheduleTypeRawValue = "monthly"
        #expect(throws: ReminderRuleDecodingError.unknownScheduleType("monthly")) {
            try rule.decodedRecurrence()
        }

        rule.scheduleTypeRawValue = TaskRecurrenceKind.once.rawValue
        rule.startDateKey = "2026-09-22"
        #expect(throws: ReminderRuleDecodingError.inconsistentOnceRange) {
            try rule.decodedRecurrence()
        }
    }

    private func seedAndComplete(storeURL: URL, templateID: UUID) throws {
        let context = try ModelContext(AppModelContainer.make(storeURL: storeURL))
        let monday = try localDate("2026-09-21")
        let tuesday = try localDate("2026-09-22")
        let recurrence = try TaskRecurrence.weekly(
            on: [.monday, .tuesday],
            starting: monday
        )
        let template = TaskTemplate(
            id: templateID,
            title: "阅读",
            iconName: "book.fill",
            colorToken: "reading",
            targetDurationSeconds: 900
        )
        let rule = ReminderRule(
            taskTemplateID: templateID,
            recurrence: recurrence,
            timeOfDayMinutes: 19 * 60 + 30
        )
        let holiday = DayOverride(date: tuesday, dayType: .holiday, note: "家庭活动")
        template.reminderRule = rule
        context.insert(template)
        context.insert(holiday)
        try context.save()

        let generated = try expander().expand(
            try rule.decodedRecurrence(),
            timeOfDayMinutes: rule.timeOfDayMinutes,
            from: monday,
            through: tuesday
        )
        let resolved = try TaskCandidateOverrideResolver().resolve(
            generated: generated,
            templateRevision: template.revision,
            dayOverrides: [.init(date: tuesday, dayType: .holiday)],
            detachedOverrides: []
        )
        _ = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: resolved,
            in: monday...tuesday,
            today: monday,
            now: try instant("2026-09-21T01:00:00Z")
        )

        let occurrence = try #require(
            context.fetch(FetchDescriptor<TaskOccurrence>()).first
        )
        let startedAt = occurrence.scheduledAt
        let progress = TaskProgressService(context: context)
        _ = try progress.startTiming(for: occurrence, at: startedAt)
        _ = try progress.complete(
            occurrence,
            at: startedAt.addingTimeInterval(900),
            source: .childManual
        )
    }

    private func reviseTemplateAfterReopen(storeURL: URL, templateID: UUID) throws {
        let context = try ModelContext(AppModelContainer.make(storeURL: storeURL))
        let template = try #require(
            context.fetch(FetchDescriptor<TaskTemplate>()).first
        )
        let rule = try #require(template.reminderRule)
        let monday = try localDate("2026-09-21")
        let wednesday = try localDate("2026-09-23")

        template.title = "每日阅读"
        template.targetDurationSeconds = 1_200
        template.revision = 2
        let revisedWeekdays: Set<Weekday> = [.monday, .wednesday]
        rule.weekdayMask = revisedWeekdays.reduce(into: 0) { mask, weekday in
            mask |= 1 << weekday.rawValue
        }
        let generated = try expander().expand(
            try rule.decodedRecurrence(),
            timeOfDayMinutes: rule.timeOfDayMinutes,
            from: monday,
            through: wednesday
        )
        let resolved = try TaskCandidateOverrideResolver().resolve(
            generated: generated,
            templateRevision: template.revision,
            dayOverrides: [],
            detachedOverrides: []
        )

        _ = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: resolved,
            in: monday...wednesday,
            today: monday,
            now: try instant("2026-09-21T13:00:00Z")
        )
        #expect(template.id == templateID)
    }

    private func verifyFinalStore(storeURL: URL, templateID: UUID) throws {
        let context = try ModelContext(AppModelContainer.make(storeURL: storeURL))
        let occurrences = try context.fetch(
            FetchDescriptor<TaskOccurrence>(sortBy: [SortDescriptor(\.dateKey)])
        )
        let monday = try #require(occurrences.first)
        let wednesday = try #require(occurrences.last)

        #expect(occurrences.count == 2)
        #expect(monday.templateID == templateID)
        #expect(monday.dateKey == "2026-09-21")
        #expect(monday.status == .completed)
        #expect(monday.titleSnapshot == "阅读")
        #expect(monday.targetDurationSnapshot == 900)
        #expect(monday.completionRecord?.activeDurationSeconds == 900)
        #expect(monday.timerSessions.count == 1)
        #expect(monday.timerSessions.first?.state == .ended)
        #expect(wednesday.dateKey == "2026-09-23")
        #expect(wednesday.status == .pending)
        #expect(wednesday.titleSnapshot == "每日阅读")
        #expect(wednesday.targetDurationSnapshot == 1_200)
        #expect(wednesday.origin == .generated(templateRevision: 2))
        #expect(try context.fetchCount(FetchDescriptor<DayOverride>()) == 1)
    }

    private func expander() throws -> TaskRecurrenceExpander {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        return TaskRecurrenceExpander(
            calendar: .init(identifier: .gregorian),
            timeZone: timeZone
        )
    }

    private func localDate(_ key: String) throws -> LocalDate {
        try LocalDate(dateKey: key)
    }

    private func instant(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }
}
