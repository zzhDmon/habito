import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("SwiftData 唯一性与删除规则")
struct PersistenceConstraintTests {
    @Test("删除按稳定外键清理断开的拥有记录，且不触碰其他实例")
    func explicitDeletionIsScopedAndRemovesOrphanedOwnedRecords() throws {
        let fixture = try TodayQueryFixture()
        let target = fixture.makeOccurrence(title: "删除目标", scheduledAt: fixture.now, status: .pending)
        let other = fixture.makeOccurrence(title: "保留任务", scheduledAt: fixture.now, status: .pending)
        let orphan = CompletionRecord(
            occurrenceID: target.id, completedAt: fixture.now, activeDurationSeconds: 0, completionSource: .childManual)
        let targetLink = NotificationLink(
            requestIdentifier: NotificationRequestIdentifier(occurrenceID: target.id, kind: .primary).rawValue,
            occurrenceID: target.id, kind: .primary, scheduledAt: fixture.now
        )
        let otherLink = NotificationLink(
            requestIdentifier: NotificationRequestIdentifier(occurrenceID: other.id, kind: .primary).rawValue,
            occurrenceID: other.id, kind: .primary, scheduledAt: fixture.now
        )
        fixture.context.insert(orphan)
        fixture.context.insert(targetLink)
        fixture.context.insert(otherLink)
        try fixture.context.save()
        try TaskGraphDeletionService(context: fixture.context).stageOccurrenceDeletion(target)
        try fixture.context.save()
        let occurrences = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())
        #expect(occurrences.map(\.id) == [other.id])
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try fixture.context.fetch(FetchDescriptor<NotificationLink>()).map(\.occurrenceID) == [other.id])
    }

    @Test("跨 context 删除被拒绝，原任务与拥有记录保持不变")
    func deletionRejectsForeignContextBeforeMutation() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "保留任务", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        let otherContext = ModelContext(fixture.context.container)
        #expect(throws: TaskGraphDeletionError.modelNotInContext) {
            try TaskGraphDeletionService(context: otherContext).stageOccurrenceDeletion(occurrence)
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
    }

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

    @Test("统一删除服务物理删除模板时保留历史实例并清理规则")
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

        context.insert(template)
        context.insert(rule)
        context.insert(occurrence)
        template.reminderRule = rule
        rule.taskTemplate = template
        occurrence.template = template
        try context.save()

        try TaskGraphDeletionService(context: context).stageTemplateDeletionPreservingHistory(template)
        try context.save()

        // 用新 context 验证落盘真相，不让旧 context 已删除对象的注册缓存影响结果。
        let verificationContext = ModelContext(container)
        let remainingOccurrences = try verificationContext.fetch(FetchDescriptor<TaskOccurrence>())
        #expect(try verificationContext.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(try verificationContext.fetchCount(FetchDescriptor<ReminderRule>()) == 0)
        #expect(remainingOccurrences.count == 1)
        #expect(remainingOccurrences.first?.template == nil)
        #expect(remainingOccurrences.first?.templateID == templateID)
    }

    @Test("统一删除服务清理实例拥有的完成计时和通知映射")
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

        context.insert(occurrence)
        context.insert(completion)
        context.insert(session)
        context.insert(link)
        occurrence.completionRecord = completion
        completion.occurrence = occurrence
        session.occurrence = occurrence
        link.occurrence = occurrence
        try context.save()

        try TaskGraphDeletionService(context: context).stageOccurrenceDeletion(occurrence)
        try context.save()

        let verificationContext = ModelContext(container)
        #expect(try verificationContext.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        #expect(try verificationContext.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try verificationContext.fetchCount(FetchDescriptor<TimerSession>()) == 0)
        #expect(try verificationContext.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }
}
