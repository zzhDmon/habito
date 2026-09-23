import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("任务执行页计时恢复")
struct TaskSessionViewModelTests {
    @Test("开始任务只创建一个活动会话")
    func startCreatesOnlyOneActiveSession() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "阅读",
            scheduledAt: fixture.now,
            status: .pending
        )
        try fixture.context.save()
        let model = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)

        model.load()
        #expect(try loadedContent(from: model.state).primaryAction == .start)

        model.startOrResume()
        model.startOrResume()

        let content = try loadedContent(from: model.state)
        #expect(content.task.status == .inProgress)
        #expect(content.primaryAction == .pause)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).count == 1)
    }

    @Test("暂停后锁屏两分钟不增长，继续后按时间戳恢复且不重复会话")
    func pauseAndResumeRecoverFromPersistedTimestamps() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "练字",
            scheduledAt: fixture.now,
            status: .pending
        )
        try fixture.context.save()
        let startedAt = fixture.now.addingTimeInterval(-120)
        try TaskProgressService(context: fixture.context).startTiming(
            for: occurrence,
            at: startedAt
        )

        let runningModel = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        runningModel.load()
        let running = try loadedContent(from: runningModel.state)
        #expect(running.displayedActiveDuration(at: fixture.now) == 120)

        runningModel.pause()
        let lockedUntil = fixture.now.addingTimeInterval(120)
        let lockedModel = makeModel(for: occurrence.id, fixture: fixture, now: lockedUntil)
        lockedModel.load()
        let paused = try loadedContent(from: lockedModel.state)
        #expect(paused.primaryAction == .resume)
        #expect(paused.displayedActiveDuration(at: lockedUntil) == 120)

        lockedModel.startOrResume()
        let foregroundAt = lockedUntil.addingTimeInterval(60)
        let restoredModel = makeModel(for: occurrence.id, fixture: fixture, now: foregroundAt)
        restoredModel.load()
        let restored = try loadedContent(from: restoredModel.state)
        #expect(restored.primaryAction == .pause)
        #expect(restored.displayedActiveDuration(at: foregroundAt) == 180)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).count == 1)
    }

    @Test("实例被移除后加载进入可重试错误态")
    func missingOccurrenceProducesFailureState() throws {
        let fixture = try TodayQueryFixture()
        let model = makeModel(for: UUID(), fixture: fixture, now: fixture.now)

        model.load()

        #expect(model.state == .failed)
    }

    private func makeModel(
        for occurrenceID: UUID,
        fixture: TodayQueryFixture,
        now: Date
    ) -> TaskSessionViewModel {
        TaskSessionViewModel(
            occurrenceID: occurrenceID,
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: now)
        )
    }

    private func loadedContent(from state: TaskSessionViewState) throws
        -> TaskSessionScreenContent
    {
        guard case let .loaded(content) = state else {
            Issue.record("预期任务执行页加载成功")
            throw TaskSessionViewModelTestError.expectedLoadedState
        }
        return content
    }

    private func sessions(in context: ModelContext, occurrenceID: UUID) throws -> [TimerSession] {
        let id = occurrenceID
        return try context.fetch(
            FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == id })
        )
    }
}

private enum TaskSessionViewModelTestError: Error {
    case expectedLoadedState
}
