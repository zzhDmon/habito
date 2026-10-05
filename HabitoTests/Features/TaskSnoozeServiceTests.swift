import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("十分钟稍后提醒")
struct TaskSnoozeServiceTests {
    @Test("稍后操作等待期间提交，不能复活等待实例的通知", arguments: [0, 1, 2])
    func submissionDuringSchedulingCannotLeaveRequest(stage: Int) async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        let submit = {
            _ = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        }
        if stage == 2 {
            fixture.scheduler.onAdd = submit
        } else {
            let duringDiagnostics: () async -> Void = {
                do { try submit() } catch { Issue.record(error) }
            }
            if stage == 0 {
                fixture.permissions.onDiagnostics = duringDiagnostics
            } else {
                fixture.scheduler.onRead = { fixture.permissions.onDiagnostics = duringDiagnostics }
            }
        }
        await #expect(throws: TaskSubmissionError.awaitingReview(occurrence.id)) {
            _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        // add 已成功才发现等待时必须补偿取消；更早发现则不应触碰系统排程。
        #expect(fixture.scheduler.addCount == (stage == 2 ? 1 : 0))
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }

    @Test("添加前权限复核期间完成或删除任务，重新查询后拒绝旧请求", arguments: [true, false])
    func businessChangesDuringPreAddDiagnosticsDoNotAddRequest(deleteOccurrence: Bool) async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        let occurrenceID = occurrence.id
        // 只在预算读取后安装一次回调，精确定位第二次权限等待，而不是依赖真实延时。
        fixture.scheduler.onRead = {
            fixture.permissions.onDiagnostics = {
                do {
                    if deleteOccurrence {
                        fixture.context.delete(occurrence)
                        try fixture.context.save()
                    } else {
                        _ = try TaskProgressService(context: fixture.context).complete(
                            occurrence, at: fixture.now, source: .childManual)
                    }
                } catch {
                    Issue.record(error)
                }
            }
        }
        if deleteOccurrence {
            await #expect(throws: TaskSnoozeError.occurrenceNotFound(occurrenceID)) {
                _ = try await fixture.service.schedule(occurrenceID: occurrenceID, at: fixture.now)
            }
        } else {
            await #expect(throws: TaskSnoozeError.invalidOccurrenceStatus(occurrenceID, "completed")) {
                _ = try await fixture.service.schedule(occurrenceID: occurrenceID, at: fixture.now)
            }
        }
        #expect(fixture.scheduler.addCount == 0)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("添加前权限等待期间取消不写系统请求，释放 gate 后可继续安排")
    func cancelledPreAddDiagnosticsDoesNotAddAndReleasesGate() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        let entered = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        fixture.scheduler.onRead = {
            fixture.permissions.onDiagnostics = {
                entered.continuation.yield(())
                var iterator = release.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
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
        #expect(fixture.scheduler.addCount == 0)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        #expect(fixture.scheduler.addCount == 1)
        #expect(fixture.scheduler.pending.count == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 1)
    }

    @Test("预算读取期间关闭授权或提醒，在系统添加前明确拒绝", arguments: [true, false], [true, false])
    func permissionsChangedDuringBudgetReadDoNotAddRequest(
        revokeAuthorization: Bool, systemWouldRejectAdding: Bool
    ) async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        // 即使系统因权限变化拒绝 add，也应由添加前复核返回明确的权限错误，不暴露泛化排程失败。
        if systemWouldRejectAdding { fixture.scheduler.addError = .addFailed }
        fixture.scheduler.onRead = {
            if revokeAuthorization {
                fixture.permissions.currentAuthorizationState = .denied
            } else {
                fixture.permissions.alertSetting = .disabled
            }
        }
        await #expect(throws: TaskSnoozeError.notificationsUnavailable) {
            _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        #expect(fixture.scheduler.addCount == 0)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        #expect(fixture.permissions.requestCount == 0)
    }

    @Test("等待读取预算期间删除实例，不向系统添加已不存在任务的请求")
    func deletionDuringBudgetReadDoesNotAddRequest() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        let occurrenceID = occurrence.id
        fixture.scheduler.onRead = {
            fixture.context.delete(occurrence)
            try fixture.context.save()
        }
        await #expect(throws: TaskSnoozeError.occurrenceNotFound(occurrenceID)) {
            _ = try await fixture.service.schedule(occurrenceID: occurrenceID, at: fixture.now)
        }
        #expect(fixture.scheduler.addCount == 0)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("系统添加期间关闭授权或提醒，不误报稍后成功且补偿清理请求", arguments: [true, false])
    func permissionsChangedDuringAddingDoNotReportSuccess(revokeAuthorization: Bool) async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        fixture.scheduler.onAdd = {
            if revokeAuthorization {
                fixture.permissions.currentAuthorizationState = .denied
            } else {
                fixture.permissions.alertSetting = .disabled
            }
        }
        await #expect(throws: TaskSnoozeError.notificationsUnavailable) {
            _ = try await fixture.service.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        #expect(fixture.permissions.requestCount == 0)
    }

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

    @Test("系统添加期间删除任务，返回后清理孤立稍后请求")
    func deletionDuringSchedulingDoesNotLeaveRequest() async throws {
        let fixture = try Fixture()
        let occurrence = try fixture.makeOccurrence()
        let occurrenceID = occurrence.id
        fixture.scheduler.onAdd = {
            fixture.context.delete(occurrence)
            try fixture.context.save()
        }
        await #expect(throws: TaskSnoozeError.occurrenceNotFound(occurrenceID)) {
            _ = try await fixture.service.schedule(occurrenceID: occurrenceID, at: fixture.now)
        }
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("排队取消的稍后操作不写入请求，也不阻塞后续操作")
    func cancelledQueuedOperationDoesNotBlockFollowingSchedule() async throws {
        let fixture = try Fixture()
        let first = try fixture.makeOccurrence(title: "先开始")
        let cancelled = try fixture.makeOccurrence(title: "取消排队")
        let last = try fixture.makeOccurrence(title: "继续排队")
        let entered = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let queued = AsyncStream.makeStream(of: Void.self)
        fixture.scheduler.onAddAsync = {
            entered.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        let firstTask = Task { try await fixture.service.schedule(occurrenceID: first.id, at: fixture.now) }
        var enteredIterator = entered.stream.makeAsyncIterator()
        _ = await enteredIterator.next()
        let cancelledTask = Task {
            queued.continuation.yield(())
            do {
                _ = try await fixture.service.schedule(occurrenceID: cancelled.id, at: fixture.now)
                return false
            } catch is CancellationError {
                return true
            }
        }
        var queuedIterator = queued.stream.makeAsyncIterator()
        _ = await queuedIterator.next()
        cancelledTask.cancel()
        let lastTask = Task { try await fixture.service.schedule(occurrenceID: last.id, at: fixture.now) }
        release.continuation.yield(())
        _ = try await firstTask.value
        #expect(try await cancelledTask.value)
        _ = try await lastTask.value
        #expect(fixture.scheduler.pending.count == 2)
        let cancelledIdentifier = NotificationRequestIdentifier(occurrenceID: cancelled.id, kind: .snooze).rawValue
        #expect(fixture.scheduler.pending[cancelledIdentifier] == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 2)
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
        var addCount = 0
        var addError: SchedulerFailure?
        var onRead: (() throws -> Void)?
        var onAdd: (() throws -> Void)?
        var onAddAsync: (() async throws -> Void)?

        func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
            if let onRead {
                self.onRead = nil
                try onRead()
            }
            return Array(pending.values)
        }

        func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
            if let addError { throw addError }
            addCount += 1
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
