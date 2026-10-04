import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("十分钟稍后提醒")
struct TaskSnoozeServiceTests {
    @Test("尚未授权或已拒绝时不排程，也不向孩子弹出权限请求", arguments: [NotificationAuthorizationState.notDetermined, .denied, .unknown])
    func unavailableAuthorizationDoesNotSchedule(_ authorization: NotificationAuthorizationState) async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        fixture.permissions.currentAuthorizationState = authorization

        await #expect(throws: TaskSnoozeError.notificationsUnavailable) {
            _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        #expect(fixture.permissions.requestCount == 0)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("提醒显示已关闭时不给出虚假的稍后提醒成功反馈")
    func disabledAlertsDoNotSchedule() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        fixture.permissions.alertSetting = .disabled
        await #expect(throws: TaskSnoozeError.notificationsUnavailable) {
            _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        #expect(fixture.scheduler.pending.isEmpty)
    }

    @Test("只关闭声音仍可安排可见提醒")
    func disabledSoundsStillAllowVisibleReminder() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        fixture.permissions.soundSetting = .disabled
        _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        #expect(fixture.scheduler.pending.count == 1)
    }

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

    @Test("等待系统添加时完成任务，返回后不能留下稍后提醒")
    func completionDuringSchedulingDoesNotLeaveRequest() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        fixture.scheduler.onAdd = {
            _ = try TaskProgressService(context: fixture.context).complete(
                occurrence, at: fixture.now, source: .childManual
            )
        }

        await #expect(throws: TaskSnoozeError.invalidOccurrenceStatus(occurrence.id, "completed")) {
            _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("七个槽位已占用时两个并发操作最多只新增一个")
    func concurrentSchedulesCannotExceedBudget() async throws {
        let fixture = try Fixture()
        var occurrences: [TaskOccurrence] = []
        for index in 0..<9 {
            occurrences.append(try fixture.makeOccurrence(title: "任务 \(index)"))
        }
        for occurrence in occurrences.prefix(7) {
            _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        let entered = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let secondStarted = AsyncStream.makeStream(of: Void.self)
        fixture.scheduler.onAddAsync = {
            entered.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        let firstID = occurrences[7].id
        let secondID = occurrences[8].id
        let first = Task { try await fixture.service.schedule(occurrenceID: firstID, at: fixture.now) }
        var enteredIterator = entered.stream.makeAsyncIterator()
        _ = await enteredIterator.next()
        let second = Task {
            secondStarted.continuation.yield(())
            do {
                _ = try await fixture.service.schedule(occurrenceID: secondID, at: fixture.now)
                return false
            } catch TaskSnoozeError.pendingLimitReached {
                return true
            }
        }
        var secondIterator = secondStarted.stream.makeAsyncIterator()
        _ = await secondIterator.next()
        release.continuation.yield(())

        _ = try await first.value
        #expect(try await second.value)
        #expect(fixture.scheduler.pending.count == 8)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 8)
    }

    @Test("添加请求期间取消操作会补偿清理，且不阻塞下一次排程")
    func cancelledScheduleCleansRequestAndReleasesGate() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        let entered = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        fixture.scheduler.onAddAsync = {
            entered.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        let scheduling = Task {
            do {
                _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
                return false
            } catch is CancellationError {
                return true
            }
        }
        var iterator = entered.stream.makeAsyncIterator()
        _ = await iterator.next()
        scheduling.cancel()
        release.continuation.yield(())
        #expect(try await scheduling.value)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)

        _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        #expect(fixture.scheduler.pending.count == 1)
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
        let permissions = FakeLocalNotificationService()

        init(now: Date? = nil) throws {
            context = ModelContext(try AppModelContainer.make(inMemory: true))
            scheduler = SnoozeSchedulerFake()
            permissions.currentAuthorizationState = .authorized
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
                permissionProvider: permissions,
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
        var onAdd: (() throws -> Void)?
        var onAddAsync: (() async throws -> Void)?

        func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
            Array(pending.values)
        }

        func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
            if let addError { throw addError }
            try onAdd?()
            if let onAddAsync {
                self.onAddAsync = nil
                try await onAddAsync()
            }
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

        func deliveredNotificationIdentifiers() async throws -> [String] { [] }

        func removeDeliveredNotificationRequest(identifier: String) async throws {}
    }

    enum SchedulerFailure: Error, Equatable {
        case addFailed
    }
}
