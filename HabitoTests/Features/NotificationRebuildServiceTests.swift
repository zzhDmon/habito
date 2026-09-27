import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("通知业务重建")
@MainActor
struct NotificationRebuildServiceTests {
    @Test("连续五次重建仅首次添加且记录覆盖检查点")
    func fiveRebuildsAreIdempotent() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()

        var results: [NotificationRebuildResult] = []
        for _ in 0..<5 {
            results.append(try await fixture.service.rebuild(at: fixture.now))
        }

        #expect(fixture.scheduler.addCount == 15)
        #expect(fixture.scheduler.pending.count == 15)
        #expect(results[0].reconciliation.addedIdentifiers.count == 15)
        #expect(
            results.dropFirst().allSatisfy {
                $0.reconciliation.retainedIdentifiers.count == 15
                    && $0.reconciliation.addedIdentifiers.isEmpty
                    && $0.reconciliation.replacedIdentifiers.isEmpty
                    && $0.reconciliation.removedIdentifiers.isEmpty
            }
        )
        #expect(results.allSatisfy { $0.selection.hasMinimumCoverage })
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 15)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 15)

        let settings = try #require(fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.lastInstanceGenerationAt == fixture.now)
        #expect(settings.lastNotificationSchedulingAt == fixture.now)
        #expect(settings.schedulingHorizonDateKey == "2026-10-11")
    }

    @Test("放假过滤实例，完成与停用后清理系统请求和映射")
    func holidayCompletionAndDisableCleanNotifications() async throws {
        let fixture = try Fixture()
        let template = try fixture.insertDailyTemplate()
        let holiday = try LocalDate(dateKey: "2026-09-28")
        fixture.context.insert(DayOverride(date: holiday, dayType: .holiday, updatedAt: fixture.now))
        try fixture.context.save()

        let first = try await fixture.service.rebuild(at: fixture.now)
        let occurrences = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())

        #expect(first.reconciliation.addedIdentifiers.count == 14)
        #expect(!occurrences.contains { $0.dateKey == holiday.dateKey })

        let completed = try #require(
            occurrences.first { $0.dateKey == "2026-09-27" }
        )
        _ = try TaskProgressService(context: fixture.context).complete(
            completed,
            at: fixture.now,
            source: .childManual
        )
        let today = try LocalDate(dateKey: "2026-09-27")
        _ = try TaskTemplateLifecycleService(
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone
        ).perform(
            templateID: template.id,
            action: .disable,
            today: today,
            now: fixture.now
        )

        let second = try await fixture.service.rebuild(at: fixture.now)

        #expect(second.selection.primaryCandidates.isEmpty)
        #expect(second.reconciliation.removedIdentifiers.count == 14)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        let remaining = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == completed.id)
        #expect(remaining.first?.status == .completed)
    }
}

@MainActor
private extension NotificationRebuildServiceTests {
    final class Fixture {
        let context: ModelContext
        let scheduler: RebuildSchedulerFake
        let service: NotificationRebuildService
        let now: Date
        let calendar: Calendar
        let timeZone: TimeZone

        init() throws {
            context = ModelContext(try AppModelContainer.make(inMemory: true))
            scheduler = RebuildSchedulerFake()
            now = try Date("2026-09-27T02:00:00Z", strategy: .iso8601)
            calendar = Calendar(identifier: .gregorian)
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            service = NotificationRebuildService(
                context: context,
                scheduler: scheduler,
                calendar: calendar,
                timeZone: timeZone
            )
        }

        func insertDailyTemplate() throws -> TaskTemplate {
            let start = try LocalDate(dateKey: "2026-09-27")
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
                recurrence: try .weekly(on: Set(Weekday.allCases), starting: start),
                timeOfDayMinutes: 19 * 60 + 30
            )
            template.reminderRule = rule
            rule.taskTemplate = template
            context.insert(template)
            context.insert(rule)
            try context.save()
            return template
        }
    }

    final class RebuildSchedulerFake: NotificationRequestScheduling {
        var pending: [String: PendingNotificationRequestSnapshot] = [:]
        var addCount = 0

        func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
            Array(pending.values)
        }

        func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
            addCount += 1
            pending[request.identifier] = PendingNotificationRequestSnapshot(
                identifier: request.identifier,
                title: request.title,
                body: request.body,
                scheduledAt: request.scheduledAt
            )
        }

        func removePendingNotificationRequest(identifier: String) async throws {
            pending[identifier] = nil
        }
    }
}
