import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("计时会话与完成记录服务")
struct TaskProgressServiceTests {
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
