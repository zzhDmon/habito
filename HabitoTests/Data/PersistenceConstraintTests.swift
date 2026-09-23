import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("SwiftData 唯一性与删除规则")
struct PersistenceConstraintTests {
    @Test("相同日期的覆盖由唯一属性合并为一条")
    func dayOverrideDateKeyIsUnique() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let date = try LocalDate(dateKey: "2026-09-23")

        context.insert(DayOverride(date: date, dayType: .holiday, note: "第一次"))
        context.insert(DayOverride(date: date, dayType: .schoolDay, note: "第二次"))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<DayOverride>()) == 1)
    }

    @Test("同一模板同一天的实例稳定键相同")
    func occurrenceCompositeKeyIsStable() throws {
        let templateID = UUID()
        let date = try LocalDate(dateKey: "2026-09-23")

        let firstKey = TaskOccurrence.makeUniquenessKey(templateID: templateID, dateKey: date.dateKey)
        let secondKey = TaskOccurrence.makeUniquenessKey(templateID: templateID, dateKey: date.dateKey)

        #expect(firstKey == secondKey)
    }

    @Test("同一模板同一天只能持久化一个实例")
    func occurrenceCompositeKeyIsUniqueInStore() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let templateID = UUID()
        let date = try LocalDate(dateKey: "2026-09-23")
        let timestamp = try Date("2026-09-23T11:30:00Z", strategy: .iso8601)
        let first = TaskOccurrence(
            templateID: templateID,
            date: date,
            scheduledAt: timestamp,
            titleSnapshot: "阅读",
            iconSnapshot: "book.fill",
            colorSnapshot: "reading",
            targetDurationSnapshot: 900,
            sourceRevision: 1
        )
        let second = TaskOccurrence(
            templateID: templateID,
            date: date,
            scheduledAt: timestamp,
            titleSnapshot: "新版阅读",
            iconSnapshot: "book.fill",
            colorSnapshot: "reading",
            targetDurationSnapshot: 1200,
            sourceRevision: 2
        )

        context.insert(first)
        context.insert(second)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
    }

    @Test("物理删除模板保留历史实例并级联删除规则")
    func templateDeletionPreservesOccurrenceHistory() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let templateID = UUID()
        let date = try LocalDate(dateKey: "2026-09-23")
        let recurrence = TaskRecurrence.once(on: date)
        let scheduledAt = try Date("2026-09-23T11:30:00Z", strategy: .iso8601)
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
        let occurrence = TaskOccurrence(
            templateID: templateID,
            date: date,
            scheduledAt: scheduledAt,
            titleSnapshot: "阅读",
            iconSnapshot: "book.fill",
            colorSnapshot: "reading",
            targetDurationSnapshot: 900,
            sourceRevision: 1
        )

        template.reminderRule = rule
        occurrence.template = template
        context.insert(template)
        context.insert(occurrence)
        try context.save()

        context.delete(template)
        try context.save()

        let remainingOccurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
        #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReminderRule>()) == 0)
        #expect(remainingOccurrences.count == 1)
        #expect(remainingOccurrences.first?.template == nil)
        #expect(remainingOccurrences.first?.templateID == templateID)
    }

    @Test("物理删除实例级联清理完成计时和通知映射")
    func occurrenceDeletionCascadesOwnedRecords() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let templateID = UUID()
        let occurrenceID = UUID()
        let date = try LocalDate(dateKey: "2026-09-23")
        let timestamp = try Date("2026-09-23T11:30:00Z", strategy: .iso8601)
        let occurrence = TaskOccurrence(
            id: occurrenceID,
            templateID: templateID,
            date: date,
            scheduledAt: timestamp,
            titleSnapshot: "阅读",
            iconSnapshot: "book.fill",
            colorSnapshot: "reading",
            targetDurationSnapshot: 900,
            sourceRevision: 1
        )
        let completion = CompletionRecord(
            occurrenceID: occurrenceID,
            completedAt: timestamp,
            activeDurationSeconds: 900,
            completionSource: .parentCorrection
        )
        let session = TimerSession(
            occurrenceID: occurrenceID,
            state: .ended,
            startedAt: timestamp,
            lastResumedAt: timestamp,
            endedAt: timestamp
        )
        let link = NotificationLink(
            requestIdentifier: "occurrence.\(occurrenceID.uuidString).primary",
            occurrenceID: occurrenceID,
            kind: .primary,
            scheduledAt: timestamp
        )

        occurrence.completionRecord = completion
        session.occurrence = occurrence
        link.occurrence = occurrence
        context.insert(occurrence)
        context.insert(session)
        context.insert(link)
        try context.save()

        context.delete(occurrence)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TimerSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }
}
