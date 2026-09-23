import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("任务模板生命周期事务")
@MainActor
struct TaskTemplateLifecycleServiceTests {
    @Test("停用预览准确且只清理未来普通待处理实例")
    func disableRemovesOnlyMutableOccurrences() throws {
        let fixture = try Fixture()
        let past = try fixture.makeOccurrence("2026-09-22", status: .pending)
        let removable = try fixture.makeOccurrence("2026-09-24", status: .pending)
        let running = try fixture.makeOccurrence("2026-09-25", status: .inProgress)
        let completed = try fixture.makeOccurrence("2026-09-26", status: .completed)
        let detached = try fixture.makeOccurrence("2026-09-27", status: .pending, detached: true)
        try fixture.context.save()

        let preview = try fixture.service.preview(
            templateID: fixture.template.id,
            action: .disable,
            today: fixture.today
        )
        #expect(preview.removableOccurrenceCount == 1)
        #expect(preview.preservedOccurrenceCount == 4)

        let result = try fixture.service.perform(
            templateID: fixture.template.id,
            action: .disable,
            today: fixture.today,
            now: fixture.now
        )
        let remaining = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())

        #expect(fixture.template.lifecycleState == .disabled)
        #expect(fixture.template.reminderRule?.isEnabled == false)
        #expect(fixture.template.revision == 2)
        #expect(result.reconciliationReport?.deletedCount == 1)
        #expect(Set(remaining.map(\.id)) == [past.id, running.id, completed.id, detached.id])
        #expect(!remaining.contains { $0.id == removable.id })
    }

    @Test("软删除进入归档终态并保留历史")
    func archivePreservesHistory() throws {
        let fixture = try Fixture()
        let history = try fixture.makeOccurrence("2026-09-22", status: .completed)
        _ = try fixture.makeOccurrence("2026-09-24", status: .pending)
        try fixture.context.save()

        _ = try fixture.service.perform(
            templateID: fixture.template.id,
            action: .archive,
            today: fixture.today,
            now: fixture.now
        )
        let remaining = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())

        #expect(fixture.template.lifecycleState == .archived)
        #expect(fixture.template.archivedAt == fixture.now)
        #expect(remaining.map(\.id) == [history.id])
        #expect(throws: DomainStateTransitionError(state: "archived", action: "enable")) {
            try fixture.service.preview(
                templateID: fixture.template.id,
                action: .enable,
                today: fixture.today
            )
        }
    }

    @Test("重新启用模板与规则且不改写保留实例")
    func enableRestoresTemplateAndRule() throws {
        let fixture = try Fixture(enabled: false)
        let occurrence = try fixture.makeOccurrence("2026-09-24", status: .completed)
        try fixture.context.save()

        let result = try fixture.service.perform(
            templateID: fixture.template.id,
            action: .enable,
            today: fixture.today,
            now: fixture.now
        )

        #expect(fixture.template.lifecycleState == .active)
        #expect(fixture.template.reminderRule?.isEnabled == true)
        #expect(result.reconciliationReport == nil)
        #expect(try fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).map(\.id) == [occurrence.id])
    }

    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let template: TaskTemplate
        let service: TaskTemplateLifecycleService
        let today: LocalDate
        let now: Date
        private let timeZone: TimeZone

        init(enabled: Bool = true) throws {
            container = try AppModelContainer.make(inMemory: true)
            context = container.mainContext
            today = try LocalDate(dateKey: "2026-09-23")
            now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            template = TaskTemplate(
                title: "阅读",
                iconName: "book.fill",
                colorToken: "reading",
                targetDurationSeconds: 900,
                isEnabled: enabled
            )
            let recurrence = try TaskRecurrence.weekly(
                on: Set(Weekday.allCases),
                starting: today
            )
            let rule = ReminderRule(
                taskTemplateID: template.id,
                recurrence: recurrence,
                timeOfDayMinutes: 19 * 60 + 30,
                isEnabled: enabled
            )
            template.reminderRule = rule
            rule.taskTemplate = template
            context.insert(template)
            context.insert(rule)
            try context.save()
            service = TaskTemplateLifecycleService(context: context)
        }

        func makeOccurrence(
            _ dateKey: String,
            status: TaskOccurrenceStatus,
            detached: Bool = false
        ) throws -> TaskOccurrence {
            let date = try LocalDate(dateKey: dateKey)
            let scheduledAt = try #require(
                TaskRecurrenceExpander(calendar: .init(identifier: .gregorian), timeZone: timeZone)
                    .expand(
                        .once(on: date),
                        timeOfDayMinutes: 19 * 60 + 30,
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
                isDetachedOverride: detached
            )
            occurrence.template = template
            context.insert(occurrence)
            return occurrence
        }
    }
}
