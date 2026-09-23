import Foundation
import Testing
@testable import Habito

@MainActor
@Suite("今日任务查询与推荐排序")
struct TodayTaskQueryServiceTests {
    @Test("无任务时返回空进度且没有推荐")
    func noTasksProducesEmptySnapshot() throws {
        let fixture = try TodayQueryFixture()

        let snapshot = try fixture.snapshot()

        #expect(snapshot.tasks.isEmpty)
        #expect(snapshot.recommendedTaskID == nil)
        #expect(snapshot.completedCount == 0)
        #expect(snapshot.totalCount == 0)
        #expect(snapshot.isEmpty)
        #expect(!snapshot.isAllCompleted)
        #expect(snapshot.isCurrentDate)
    }

    @Test("全部完成时没有推荐并返回完整进度")
    func allCompletedProducesCompleteProgress() throws {
        let fixture = try TodayQueryFixture()
        let early = fixture.makeOccurrence(
            title: "阅读",
            scheduledAt: try instant("2026-09-23T01:00:00Z"),
            status: .completed
        )
        let late = fixture.makeOccurrence(
            title: "练字",
            scheduledAt: try instant("2026-09-23T03:00:00Z"),
            status: .completed
        )
        fixture.addCompletion(to: early, at: try instant("2026-09-23T01:20:00Z"))
        fixture.addCompletion(to: late, at: try instant("2026-09-23T03:20:00Z"))

        let snapshot = try fixture.snapshot()

        #expect(snapshot.tasks.map(\.id) == [early.id, late.id])
        #expect(snapshot.recommendedTaskID == nil)
        #expect(snapshot.completedCount == 2)
        #expect(snapshot.totalCount == 2)
        #expect(snapshot.isAllCompleted)
    }

    @Test("多个逾期任务按最早计划时间优先于即将开始和已完成")
    func overdueTasksUseEarliestFirstOrdering() throws {
        let fixture = try TodayQueryFixture()
        let completed = fixture.makeOccurrence(
            title: "已完成",
            scheduledAt: try instant("2026-09-23T00:00:00Z"),
            status: .completed
        )
        fixture.addCompletion(to: completed, at: try instant("2026-09-23T00:30:00Z"))
        let laterOverdue = fixture.makeOccurrence(
            title: "较晚逾期",
            scheduledAt: try instant("2026-09-23T03:00:00Z"),
            status: .pending
        )
        let future = fixture.makeOccurrence(
            title: "即将开始",
            scheduledAt: try instant("2026-09-23T06:00:00Z"),
            status: .pending
        )
        let earliestOverdue = fixture.makeOccurrence(
            title: "最早逾期",
            scheduledAt: try instant("2026-09-23T01:00:00Z"),
            status: .pending
        )

        let snapshot = try fixture.snapshot()

        #expect(
            snapshot.tasks.map(\.id)
                == [earliestOverdue.id, laterOverdue.id, future.id, completed.id]
        )
        #expect(snapshot.recommendedTaskID == earliestOverdue.id)
        #expect(snapshot.completedCount == 1)
        #expect(snapshot.totalCount == 4)
    }

    @Test("进行中任务优先并按时间戳恢复累计活动时长")
    func inProgressTaskWinsAndRestoresDuration() throws {
        let fixture = try TodayQueryFixture()
        _ = fixture.makeOccurrence(
            title: "逾期任务",
            scheduledAt: try instant("2026-09-23T01:00:00Z"),
            status: .pending
        )
        let active = fixture.makeOccurrence(
            title: "正在阅读",
            scheduledAt: try instant("2026-09-23T06:00:00Z"),
            status: .inProgress
        )
        fixture.addSession(
            to: active,
            state: .ended,
            startedAt: try instant("2026-09-23T02:00:00Z"),
            lastResumedAt: try instant("2026-09-23T02:00:00Z"),
            accumulatedSeconds: 300,
            endedAt: try instant("2026-09-23T02:05:00Z")
        )
        fixture.addSession(
            to: active,
            state: .running,
            startedAt: try instant("2026-09-23T03:50:00Z"),
            lastResumedAt: try instant("2026-09-23T03:59:00Z"),
            accumulatedSeconds: 120
        )

        let snapshot = try fixture.snapshot()
        let first = try #require(snapshot.tasks.first)

        #expect(first.id == active.id)
        #expect(snapshot.recommendedTaskID == active.id)
        #expect(first.activeSessionState == .running)
        #expect(first.activeDurationSeconds == 480)
    }

    @Test("昨日进行中任务优先展示且不计入今日进度")
    func carryOverTaskIsRecommendedWithoutChangingTodayProgress() throws {
        let fixture = try TodayQueryFixture()
        let yesterday = try LocalDate(dateKey: "2026-09-22")
        let carryOver = fixture.makeOccurrence(
            title: "昨日阅读",
            scheduledAt: try instant("2026-09-22T11:30:00Z"),
            status: .inProgress,
            date: yesterday
        )
        fixture.addSession(
            to: carryOver,
            state: .running,
            startedAt: try instant("2026-09-22T11:30:00Z"),
            lastResumedAt: try instant("2026-09-22T11:30:00Z"),
            accumulatedSeconds: 0
        )

        let snapshot = try fixture.snapshot()

        #expect(snapshot.tasks.isEmpty)
        #expect(snapshot.carryOverTasks.map(\.id) == [carryOver.id])
        #expect(snapshot.visibleTasks.map(\.id) == [carryOver.id])
        #expect(snapshot.recommendedTaskID == carryOver.id)
        #expect(snapshot.completedCount == 0)
        #expect(snapshot.totalCount == 0)
        #expect(!snapshot.isEmpty)
        #expect(!snapshot.isAllCompleted)
    }

    @Test("跳过任务不进入孩子进度也不会被推荐")
    func skippedTaskIsExcludedFromChildProgress() throws {
        let fixture = try TodayQueryFixture()
        let skipped = fixture.makeOccurrence(
            title: "已跳过",
            scheduledAt: try instant("2026-09-23T01:00:00Z"),
            status: .skipped
        )

        let snapshot = try fixture.snapshot()

        #expect(snapshot.tasks.map(\.id) == [skipped.id])
        #expect(snapshot.visibleTasks.isEmpty)
        #expect(snapshot.totalCount == 0)
        #expect(snapshot.recommendedTaskID == nil)
    }

    @Test("损坏的实例状态会明确报错")
    func invalidStatusIsRejected() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "损坏任务",
            scheduledAt: try instant("2026-09-23T01:00:00Z"),
            status: .pending
        )
        occurrence.statusRawValue = "unknown"

        #expect(
            throws: TodayTaskQueryError.invalidOccurrenceStatus(
                occurrenceID: occurrence.id,
                value: "unknown"
            )
        ) {
            try fixture.snapshot()
        }
    }

    private func instant(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }
}
