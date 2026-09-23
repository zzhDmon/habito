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
