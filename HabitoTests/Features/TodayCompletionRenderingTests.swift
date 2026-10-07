import SwiftUI
import Testing
@testable import Habito

/// 静态印章没有动画状态，减少动态效果的首帧仍显示完整结果；这里只验渲染，不替代系统开关实测。
@MainActor
struct TodayCompletionRenderingTests {
    @Test("完成印章在窄宽与横屏各字号自然换行", arguments: [320, 900], [false, true])
    func resultRenders(width: Int, maximumTextSize: Bool) throws {
        let summary = try #require(TodayScreenContent.previewCompleted.dailyCompletion)
        let renderer = ImageRenderer(
            content: KidTodayCompletionView(summary: summary)
                .environment(\.dynamicTypeSize, maximumTextSize ? .accessibility5 : .large)
                .frame(width: CGFloat(width)))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == width && image.height > 0)
    }

    @Test("任务区域空错误未全完成与已完成均可渲染", arguments: [0, 1, 2, 3], [false, true])
    func taskStatesRender(variant: Int, maximumTextSize: Bool) throws {
        let state: TodayViewState =
            switch variant {
            case 0:
                .loaded(
                    TodayScreenContent(
                        recommendedTask: nil, remainingTasks: [], completedCount: 0, totalCount: 0,
                        isAllCompleted: false))
            case 1: .failed
            case 2: .loaded(.preview)
            default: .loaded(.previewCompleted)
            }
        let renderer = ImageRenderer(
            content: KidTodayTaskContent(
                state: state, makeTimingPresentation: KidTaskTimingPresentation.preview,
                onSelectTask: { _ in }, onRetry: {}
            )
            .environment(\.dynamicTypeSize, maximumTextSize ? .accessibility5 : .large).frame(width: 320))
        renderer.scale = 1
        #expect(try #require(renderer.cgImage).height > 0)
    }
}
