import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("十分钟稍后提醒")
struct TaskSnoozeServiceTests {
    @Test("同一实例连续操作只保留最新请求和一个映射")
    func repeatedScheduleReplacesStableSlot() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()

        let firstDate = try await fixture.service.schedule(
            occurrenceID: occurrence.id,
            at: fixture.now
        )
        let secondNow = fixture.now.addingTimeInterval(120)
        let secondDate = try await fixture.service.schedule(
            occurrenceID: occurrence.id,
            at: secondNow
        )

        let identifier = NotificationRequestIdentifier(
            occurrenceID: occurrence.id,
            kind: .snooze
        ).rawValue
        #expect(firstDate == fixture.now.addingTimeInterval(600))
        #expect(secondDate == secondNow.addingTimeInterval(600))
        #expect(fixture.scheduler.pending.count == 1)
        #expect(fixture.scheduler.pending[identifier]?.scheduledAt == secondDate)

        let links = try fixture.context.fetch(FetchDescriptor<NotificationLink>())
        #expect(links.count == 1)
        #expect(links.first?.requestIdentifier == identifier)
        #expect(links.first?.scheduledAt == secondDate)
    }

    @Test("第八条可创建，第九条拒绝，但已有槽位仍可替换")
    func pendingBudgetAllowsReplacementAtLimit() async throws {
        let fixture = try Fixture()
        var occurrences: [TaskOccurrence] = []
        for index in 0..<9 {
            occurrences.append(try fixture.makeOccurrence(title: "任务 \(index)"))
        }

        for occurrence in occurrences.prefix(8) {
            _ = try await fixture.service.schedule(
                occurrenceID: occurrence.id,
                at: fixture.now
            )
        }
        #expect(fixture.scheduler.pending.count == 8)

        await #expect(throws: TaskSnoozeError.pendingLimitReached(8)) {
            _ = try await fixture.service.schedule(
                occurrenceID: occurrences[8].id,
                at: fixture.now
            )
        }

        _ = try await fixture.service.schedule(
            occurrenceID: occurrences[0].id,
            at: fixture.now.addingTimeInterval(60)
        )
        #expect(fixture.scheduler.pending.count == 8)
    }

    @Test("二十三点五十五分操作不会把今天任务提醒到次日")
    func crossingMidnightIsRejected() async throws {
        let lateNow = try Date("2026-09-29T15:55:00Z", strategy: .iso8601)
        let fixture = try Fixture(now: lateNow)
        let occurrence = try fixture.makeOccurrence()

        await #expect(throws: TaskSnoozeError.crossesLocalMidnight) {
            _ = try await fixture.service.schedule(
                occurrenceID: occurrence.id,
                at: lateNow
            )
        }

        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("系统排程失败不会写入映射")
    func schedulingFailureDoesNotPersistLink() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        fixture.scheduler.addError = SchedulerFailure.addFailed

        await #expect(throws: SchedulerFailure.addFailed) {
            _ = try await fixture.service.schedule(
                occurrenceID: occurrence.id,
                at: fixture.now
            )
        }

        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }
}

@MainActor
private extension TaskSnoozeServiceTests {
    final class Fixture {
        let context: ModelContext
        let scheduler: SnoozeSchedulerFake
        let service: TaskSnoozeService
        let now: Date
        let calendar: Calendar
        let timeZone: TimeZone

        init(now: Date? = nil) throws {
            context = ModelContext(try AppModelContainer.make(inMemory: true))
            scheduler = SnoozeSchedulerFake()
            if let now {
                self.now = now
            } else {
                self.now = try Date("2026-09-29T12:00:00Z", strategy: .iso8601)
            }
            calendar = Calendar(identifier: .gregorian)
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            service = TaskSnoozeService(
                context: context,
                scheduler: scheduler,
                calendar: calendar,
                timeZone: timeZone
            )
        }

        func makeOccurrence(title: String = "阅读") throws -> TaskOccurrence {
            let date = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
            let occurrence = TaskOccurrence(
                templateID: UUID(),
                date: date,
                scheduledAt: now.addingTimeInterval(-60),
                titleSnapshot: title,
                iconSnapshot: "book.fill",
                colorSnapshot: "task",
                targetDurationSnapshot: 900,
                sourceRevision: 1,
                createdAt: now,
                updatedAt: now
            )
            context.insert(occurrence)
            try context.save()
            return occurrence
        }
    }

    final class SnoozeSchedulerFake: NotificationRequestScheduling {
        var pending: [String: PendingNotificationRequestSnapshot] = [:]
        var addError: SchedulerFailure?

        func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
            Array(pending.values)
        }

        func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
            if let addError { throw addError }
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

    enum SchedulerFailure: Error, Equatable {
        case addFailed
    }
}
