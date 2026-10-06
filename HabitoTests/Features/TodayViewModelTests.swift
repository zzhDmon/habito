import Foundation
import Testing
@testable import Habito

@MainActor
@Suite("孩子今日页状态")
struct TodayViewModelTests {
    @Test("加载后推荐项保留查询排序和正确任务标识")
    func loadBuildsPresentationAndRecommendedRoute() throws {
        let fixture = try TodayQueryFixture()
        let recommended = fixture.makeOccurrence(
            title: "阅读",
            scheduledAt: try instant("2026-09-23T03:00:00Z"),
            status: .pending
        )
        let upcoming = fixture.makeOccurrence(
            title: "练字",
            scheduledAt: try instant("2026-09-23T06:00:00Z"),
            status: .pending
        )
        try fixture.context.save()
        let model = TodayViewModel(
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now)
        )

        model.load()

        let content = try loadedContent(from: model.state)
        #expect(content.recommendedTask?.id == recommended.id)
        #expect(content.recommendedTask?.scheduledTimeText == "11:00")
        #expect(content.recommendedTask?.targetDurationText == "15 分钟")
        #expect(content.remainingTasks.map(\.id) == [upcoming.id])
        #expect(content.completedCount == 0)
        #expect(content.totalCount == 2)
    }

    @Test("查询损坏数据时进入可重试错误态")
    func corruptedDataProducesFailureState() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "损坏任务",
            scheduledAt: try instant("2026-09-23T03:00:00Z"),
            status: .pending
        )
        occurrence.statusRawValue = "unknown"
        try fixture.context.save()
        let model = TodayViewModel(
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now)
        )

        model.load()

        #expect(model.state == .failed)
    }

    @Test("一日前或两日前进行中任务显示通用状态且仍可进入原实例", arguments: [1, 2])
    func carryOverTaskBuildsRecoverablePresentation(days: Int) throws {
        let fixture = try TodayQueryFixture()
        let earlier = fixture.now.addingTimeInterval(-Double(days) * 86400)
        let occurrence = fixture.makeOccurrence(
            title: "之前的练字",
            scheduledAt: earlier,
            status: .inProgress,
            date: try LocalDate(date: earlier, calendar: fixture.calendar, timeZone: fixture.timeZone)
        )
        fixture.addSession(
            to: occurrence,
            state: .paused,
            startedAt: earlier,
            lastResumedAt: earlier,
            accumulatedSeconds: 300
        )
        try fixture.context.save()
        let model = TodayViewModel(
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now)
        )

        model.load()

        let content = try loadedContent(from: model.state)
        #expect(!content.isEmpty)
        #expect(content.recommendedTask?.id == occurrence.id)
        #expect(content.recommendedTask?.statusText == "之前的任务还在做")
        #expect(content.completedCount == 0)
        #expect(content.totalCount == 0)
        #expect(!content.isAllCompleted)
    }

    @Test("审核等待与退回展示明确文字，但不伪装成已完成", arguments: [false, true])
    func reviewPresentationKeepsPendingFact(returned: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "审核任务", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        let row = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        if returned {
            _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
                occurrence, submissionID: row.submissionID, at: fixture.now)
        }
        let model = TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now))
        model.load()
        let content = try loadedContent(from: model.state)
        let item = try #require(content.recommendedTask ?? content.remainingTasks.first)
        #expect(item.id == occurrence.id)
        #expect(item.status == .pending)
        #expect(item.statusText == (returned ? "再完善一下" : "等家长确认"))
        #expect(item.statusIconName == (returned ? "arrow.uturn.backward.circle.fill" : "hourglass.circle.fill"))
        #expect(content.completedCount == 0)
        #expect(content.totalCount == 1)
        #expect(!content.isAllCompleted)
    }

    private func loadedContent(from state: TodayViewState) throws -> TodayScreenContent {
        guard case let .loaded(content) = state else {
            Issue.record("预期今日页加载成功")
            throw TodayViewModelTestError.expectedLoadedState
        }
        return content
    }

    private func instant(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }
}

private enum TodayViewModelTestError: Error {
    case expectedLoadedState
}
