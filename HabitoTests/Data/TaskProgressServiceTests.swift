import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("计时会话与完成记录服务")
struct TaskProgressServiceTests {
    @Test("切换先只读确认，跨午夜与普通任务共享一次边界且重试幂等", arguments: [false, true])
    func switchRequiresConfirmationAndIsIdempotent(crossMidnight: Bool) throws {
        let f = try TodayQueryFixture()
        let first = f.makeOccurrence(
            title: "阅读", scheduledAt: f.now.addingTimeInterval(-90), status: .pending,
            date: crossMidnight ? try LocalDate(dateKey: "2026-09-22") : f.date)
        let second = f.makeOccurrence(title: "口算", scheduledAt: f.now, status: .pending)
        try f.context.save()
        let legacy = TaskProgressService(context: f.context)
        let original = try legacy.startTiming(for: first, at: f.now.addingTimeInterval(-90))
        let switcher = TaskTimingSwitchService(context: f.context, calendar: f.calendar, timeZone: f.timeZone)
        let plan = try switcher.plan(for: second.id, at: f.now)
        #expect(plan.runningIDs == [first.id])
        #expect(original.state == .running)
        #expect(second.status == .pending)
        #expect(!f.context.hasChanges)
        #expect(throws: TaskTimingSwitchError.confirmationRequired) { try switcher.start(for: second.id, at: f.now) }
        let active = try switcher.start(for: second.id, at: f.now, confirmedRunningIDs: plan.runningIDs)
        #expect(original.state == .paused)
        #expect(original.accumulatedActiveSeconds == 90)
        #expect(active.state == .running)
        #expect(active.lastResumedAt == f.now)
        #expect(
            try switcher.start(for: second.id, at: f.now.addingTimeInterval(10), confirmedRunningIDs: plan.runningIDs)
                .id == active.id)
        #expect(active.lastResumedAt == f.now)
        #expect(try f.context.fetchCount(FetchDescriptor<TimerSession>()) == 2)
    }

    @Test("启动或继续保存失败，其他计时和目标一起回滚并可重试", arguments: [false, true])
    func switchSaveFailureRestoresBothTasks(resuming: Bool) throws {
        let f = try TodayQueryFixture()
        let first = f.makeOccurrence(title: "阅读", scheduledAt: f.now, status: .pending)
        let second = f.makeOccurrence(title: "口算", scheduledAt: f.now, status: .pending)
        try f.context.save()
        let legacy = TaskProgressService(context: f.context)
        let original = try legacy.startTiming(for: first, at: f.now.addingTimeInterval(-90))
        if resuming {
            _ = try legacy.startTiming(for: second, at: f.now.addingTimeInterval(-60))
            _ = try legacy.pauseTiming(for: second, at: f.now.addingTimeInterval(-30))
        }
        let expectedCount = resuming ? 2 : 1
        let failure = CocoaError(.fileWriteUnknown)
        let switcher = TaskTimingSwitchService(
            context: f.context, calendar: f.calendar, timeZone: f.timeZone,
            saveChanges: { context in
                #expect(original.state == .paused)
                #expect(second.status == .inProgress)
                #expect(context.hasChanges)
                throw failure
            })
        #expect(throws: failure) { try switcher.start(for: second.id, at: f.now, confirmedRunningIDs: [first.id]) }
        #expect(original.state == .running)
        #expect(original.accumulatedActiveSeconds == 0)
        #expect(second.status == (resuming ? .inProgress : .pending))
        #expect(try f.context.fetchCount(FetchDescriptor<TimerSession>()) == expectedCount)
        #expect(!f.context.hasChanges)
        let stored = ModelContext(f.context.container)
        let storedSessions = try stored.fetch(FetchDescriptor<TimerSession>())
        #expect(storedSessions.first { $0.occurrenceID == first.id }?.state == .running)
        if resuming {
            let paused = try #require(storedSessions.first { $0.occurrenceID == second.id })
            #expect(paused.state == .paused)
            #expect(paused.accumulatedActiveSeconds == 30)
            #expect(paused.lastResumedAt == f.now.addingTimeInterval(-60))
        }
        let retry = TaskTimingSwitchService(context: f.context, calendar: f.calendar, timeZone: f.timeZone)
        #expect(try retry.start(for: second.id, at: f.now, confirmedRunningIDs: [first.id]).state == .running)
    }

    @Test("存量并行先全部确认，确认期间新增任务不擅自暂停")
    func legacyParallelSessionsRequireFreshConfirmation() throws {
        let f = try TodayQueryFixture()
        let a = f.makeOccurrence(title: "阅读", scheduledAt: f.now.addingTimeInterval(-60), status: .pending)
        let b = f.makeOccurrence(title: "练字", scheduledAt: f.now.addingTimeInterval(-30), status: .pending)
        let c = f.makeOccurrence(title: "口算", scheduledAt: f.now, status: .pending)
        try f.context.save()
        let legacy = TaskProgressService(context: f.context)
        let aSession = try legacy.startTiming(for: a, at: f.now.addingTimeInterval(-60))
        let switcher = TaskTimingSwitchService(context: f.context, calendar: f.calendar, timeZone: f.timeZone)
        let oldPlan = try switcher.plan(for: c.id, at: f.now)
        let bSession = try legacy.startTiming(for: b, at: f.now.addingTimeInterval(-30))
        #expect(throws: TaskTimingSwitchError.runningTasksChanged) {
            try switcher.start(for: c.id, at: f.now, confirmedRunningIDs: oldPlan.runningIDs)
        }
        #expect(aSession.state == .running && bSession.state == .running)
        #expect(c.status == .pending)
        let currentPlan = try switcher.plan(for: c.id, at: f.now)
        #expect(currentPlan.runningTasks.map(\.id) == [a.id, b.id])
        _ = try switcher.start(for: c.id, at: f.now, confirmedRunningIDs: currentPlan.runningIDs)
        #expect(aSession.state == .paused && bSession.state == .paused)
        #expect(aSession.accumulatedActiveSeconds == 60 && bSession.accumulatedActiveSeconds == 30)
    }

    @Test("未保存草稿不被切换保存或回滚，异常会话与倒退时间也不改目标")
    func unsafePreflightDoesNotMutate() throws {
        let f = try TodayQueryFixture()
        let a = f.makeOccurrence(title: "阅读", scheduledAt: f.now, status: .pending)
        let b = f.makeOccurrence(title: "口算", scheduledAt: f.now, status: .pending)
        try f.context.save()
        let session = try TaskProgressService(context: f.context).startTiming(for: a, at: f.now)
        let switcher = TaskTimingSwitchService(context: f.context, calendar: f.calendar, timeZone: f.timeZone)
        a.titleSnapshot = "未保存标题"
        #expect(throws: RewardLedgerError.pendingContextChanges) { try switcher.plan(for: b.id, at: f.now) }
        #expect(a.titleSnapshot == "未保存标题" && f.context.hasChanges)
        try f.context.save()
        #expect(throws: (any Error).self) { try switcher.plan(for: b.id, at: f.now.addingTimeInterval(-1)) }
        session.stateRawValue = "broken"
        try f.context.save()
        #expect(throws: TaskProgressServiceError.invalidSessionState(sessionID: session.id, rawValue: "broken")) {
            try switcher.start(for: b.id, at: f.now)
        }
        #expect(b.status == .pending)
        #expect(session.stateRawValue == "broken")
    }

    @Test("等待审核目标不能通过切换重新计时")
    func waitingTargetCannotRestartThroughSwitch() throws {
        let f = try TodayQueryFixture()
        let target = f.makeOccurrence(title: "口算", scheduledAt: f.now, status: .pending)
        target.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try f.context.save()
        _ = try TaskSubmissionService(context: f.context).submit(target, at: f.now)
        let switcher = TaskTimingSwitchService(context: f.context, calendar: f.calendar, timeZone: f.timeZone)
        #expect(throws: TaskTimingSwitchError.targetUnavailable) { try switcher.start(for: target.id, at: f.now) }
        #expect(try f.context.fetchCount(FetchDescriptor<TimerSession>()) == 0)
    }

    @Test("重复开始只保留同一个活动会话")
    func repeatedStartReturnsSameSession() throws {
        let setup = try makeSetup()
        let startedAt = try instant("2026-09-23T11:00:00Z")

        let first = try setup.service.startTiming(for: setup.occurrence, at: startedAt)
        let second = try setup.service.startTiming(for: setup.occurrence, at: startedAt.addingTimeInterval(1))

        #expect(first.id == second.id)
        #expect(setup.occurrence.status == .inProgress)
        #expect(try setup.context.fetchCount(FetchDescriptor<TimerSession>()) == 1)
    }

    @Test("暂停继续按时间戳累计且重复操作不重复计时")
    func pauseResumeUsesTimestampsWithoutDoubleCounting() throws {
        let setup = try makeSetup()
        let start = try instant("2026-09-23T11:00:00Z")
        let session = try setup.service.startTiming(for: setup.occurrence, at: start)

        let paused = try setup.service.pauseTiming(
            for: setup.occurrence,
            at: start.addingTimeInterval(60)
        )
        let repeatedPause = try setup.service.pauseTiming(
            for: setup.occurrence,
            at: start.addingTimeInterval(90)
        )
        _ = try setup.service.resumeTiming(
            for: setup.occurrence,
            at: start.addingTimeInterval(120)
        )
        _ = try setup.service.resumeTiming(
            for: setup.occurrence,
            at: start.addingTimeInterval(130)
        )

        #expect(paused.id == repeatedPause.id)
        #expect(paused.accumulatedActiveSeconds == 60)
        #expect(
            try setup.service.activeDuration(
                of: session,
                at: start.addingTimeInterval(180)
            ) == 120
        )

        let ended = try setup.service.endTiming(
            for: setup.occurrence,
            at: start.addingTimeInterval(180)
        )
        #expect(ended.state == .ended)
        #expect(ended.accumulatedActiveSeconds == 120)
    }

    @Test("完成会结束活动会话且重复完成不新增记录")
    func completionEndsTimerAndIsIdempotent() throws {
        let setup = try makeSetup()
        let start = try instant("2026-09-23T11:00:00Z")
        let session = try setup.service.startTiming(for: setup.occurrence, at: start)

        let first = try setup.service.complete(
            setup.occurrence,
            at: start.addingTimeInterval(90),
            source: .childManual
        )
        let second = try setup.service.complete(
            setup.occurrence,
            at: start.addingTimeInterval(100),
            source: .childManual
        )

        #expect(first.id == second.id)
        #expect(first.activeDurationSeconds == 90)
        #expect(setup.occurrence.status == .completed)
        #expect(session.state == .ended)
        #expect(session.endedAt == start.addingTimeInterval(90))
        #expect(try setup.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
    }

    @Test("撤销后旧会话不复活且再次完成累计多段用时")
    func undoThenRestartAccumulatesEndedSessions() throws {
        let setup = try makeSetup()
        let start = try instant("2026-09-23T11:00:00Z")
        let firstSession = try setup.service.startTiming(for: setup.occurrence, at: start)
        _ = try setup.service.complete(
            setup.occurrence,
            at: start.addingTimeInterval(60),
            source: .childManual
        )

        #expect(
            try setup.service.undoCompletion(
                of: setup.occurrence,
                at: start.addingTimeInterval(70)
            )
        )
        #expect(setup.occurrence.status == .pending)
        #expect(firstSession.state == .ended)
        #expect(try setup.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(
            try !setup.service.undoCompletion(
                of: setup.occurrence,
                at: start.addingTimeInterval(80)
            )
        )

        let secondSession = try setup.service.startTiming(
            for: setup.occurrence,
            at: start.addingTimeInterval(100)
        )
        let record = try setup.service.complete(
            setup.occurrence,
            at: start.addingTimeInterval(130),
            source: .childManual
        )

        #expect(firstSession.id != secondSession.id)
        #expect(firstSession.state == .ended)
        #expect(secondSession.state == .ended)
        #expect(record.activeDurationSeconds == 90)
        #expect(try setup.context.fetchCount(FetchDescriptor<TimerSession>()) == 2)
        #expect(try setup.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
    }

    @Test("未计时任务也可手动完成且实际用时为零")
    func pendingOccurrenceCanCompleteWithoutTimer() throws {
        let setup = try makeSetup()
        let completedAt = try instant("2026-09-23T11:00:00Z")

        let record = try setup.service.complete(
            setup.occurrence,
            at: completedAt,
            source: .parentCorrection
        )

        #expect(record.activeDurationSeconds == 0)
        #expect(record.completionSource == .parentCorrection)
        #expect(setup.occurrence.status == .completed)
    }

    @Test("系统时间早于当前运行段时拒绝修改")
    func backwardsClockIsRejectedBeforeMutation() throws {
        let setup = try makeSetup()
        let start = try instant("2026-09-23T11:00:00Z")
        let session = try setup.service.startTiming(for: setup.occurrence, at: start)
        let earlier = start.addingTimeInterval(-1)

        #expect(throws: TaskProgressServiceError.timeBeforeLastResume(sessionID: session.id)) {
            try setup.service.pauseTiming(for: setup.occurrence, at: earlier)
        }
        #expect(session.state == .running)
        #expect(session.accumulatedActiveSeconds == 0)
    }

    @Test("存量存在多个活动会话时拒绝再开始")
    func multipleActiveSessionsAreRejected() throws {
        let setup = try makeSetup()
        let start = try instant("2026-09-23T11:00:00Z")
        setup.occurrence.statusRawValue = TaskOccurrenceStatus.inProgress.rawValue
        let first = TimerSession(
            occurrenceID: setup.occurrence.id,
            state: .running,
            startedAt: start,
            lastResumedAt: start
        )
        let second = TimerSession(
            occurrenceID: setup.occurrence.id,
            state: .paused,
            startedAt: start,
            lastResumedAt: start
        )
        first.occurrence = setup.occurrence
        second.occurrence = setup.occurrence
        setup.context.insert(first)
        setup.context.insert(second)
        try setup.context.save()

        #expect(
            throws: TaskProgressServiceError.multipleActiveSessions(
                occurrenceID: setup.occurrence.id
            )
        ) {
            try setup.service.startTiming(for: setup.occurrence, at: start)
        }
        #expect(try setup.context.fetchCount(FetchDescriptor<TimerSession>()) == 2)
    }

    private func makeSetup() throws -> (
        context: ModelContext,
        occurrence: TaskOccurrence,
        service: TaskProgressService
    ) {
        let context = try ModelContext(AppModelContainer.make(inMemory: true))
        let date = try LocalDate(dateKey: "2026-09-23")
        let occurrence = TaskOccurrence(
            templateID: UUID(),
            date: date,
            scheduledAt: try instant("2026-09-23T10:30:00Z"),
            titleSnapshot: "阅读",
            iconSnapshot: "book.fill",
            colorSnapshot: "reading",
            targetDurationSnapshot: 900,
            sourceRevision: 1
        )
        context.insert(occurrence)
        try context.save()
        return (context, occurrence, TaskProgressService(context: context))
    }

    private func instant(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }
}
