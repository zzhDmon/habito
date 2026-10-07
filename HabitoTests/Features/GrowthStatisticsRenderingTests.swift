import SwiftUI
import Testing
@testable import Habito

/// 原生静态渲染验证换行与各状态；真实MAX滚动和44pt仍由UI专项证明。
@MainActor
struct GrowthStatisticsRenderingTests {
    @Test("已完成家长行的来源/自主性在窄宽与MAX可渲染", arguments: [false, true])
    func completedParentRowRenders(large: Bool) throws {
        guard case let .loaded(snapshot) = GrowthStatisticsPreview.completedState else {
            throw NSError(domain: "SyntheticPreview", code: 1)
        }
        let time = Date(timeIntervalSince1970: 1_790_226_600)
        let item = TodayTaskItem(
            id: UUID(), date: snapshot.end, scheduledAt: time, title: "固定合成阅读", iconName: "book.fill",
            colorToken: "reading", targetDurationSeconds: 900, status: .completed,
            origin: .generated(templateRevision: 1), activeSessionState: nil, activeDurationSeconds: 0,
            completion: TodayTaskCompletion(
                id: UUID(), completedAt: time, activeDurationSeconds: 0,
                source: .childManual, timing: .afterReminder))
        let renderer = ImageRenderer(
            content: ParentTodayTaskRow(
                item: item, onReschedule: {}, onSkip: {}, onRestore: {}, onCorrectAsCompleted: {}
            )
            .environment(\.dynamicTypeSize, large ? .accessibility5 : .large).frame(width: 320))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height > 0)
    }

    @Test("空/0/自主完成概况在窄宽度与MAX可渲染", arguments: [0, 1, 2], [false, true])
    func countsRenderWithoutFixedFontOrHeight(variant: Int, large: Bool) throws {
        let state =
            variant == 0
            ? GrowthStatisticsPreview.emptyState
            : (variant == 1 ? GrowthStatisticsPreview.state : GrowthStatisticsPreview.completedState)
        guard case let .loaded(snapshot) = state else { throw NSError(domain: "SyntheticPreview", code: 1) }
        let renderer = ImageRenderer(
            content: GrowthStatisticsCountsView(counts: snapshot.counts, identifier: "test")
                .environment(\.dynamicTypeSize, large ? .accessibility5 : .large).frame(width: 320))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height > 0)
    }

    @Test("今日概况错误/加载/空/完成在MAX可渲染", arguments: [0, 1, 2, 3], [false, true])
    func overviewStatesRender(variant: Int, large: Bool) throws {
        guard case let .loaded(snapshot) = GrowthStatisticsPreview.completedState,
            let day = snapshot.days.last
        else { throw NSError(domain: "SyntheticPreview", code: 1) }
        let state: ParentTodayOverviewState =
            switch variant {
            case 0: .failed
            case 1: .loading
            case 2: .loaded(GrowthStatisticsDay(date: day.date, counts: .init(facts: [])))
            default: .loaded(day)
            }
        let renderer = ImageRenderer(
            content: ParentTodayOverviewView(state: state, onRetry: {}, onShowStatistics: {})
                .environment(\.dynamicTypeSize, large ? .accessibility5 : .large).frame(width: 320))
        renderer.scale = 1
        #expect(try #require(renderer.cgImage).height > 0)
    }
}
