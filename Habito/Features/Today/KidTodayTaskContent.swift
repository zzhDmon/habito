import SwiftUI

/// 今日任务的独立状态区域，不以资产加载是否成功决定任务能否查看。
struct KidTodayTaskContent: View {
    /// 系统只读环境由SwiftUI随设置刷新；只影响装饰动画，不改变完成事实或操作资格。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: TodayViewState
    let makeTimingPresentation: @MainActor (KidTaskNavigationItem) -> KidTaskTimingPresentation
    let onSelectTask: (KidTaskNavigationItem) -> Void
    let onRetry: () -> Void
    var celebrationEvent: TodayCompletionCelebrationEvent?
    var celebrationVerificationFailed = false
    var onClaimCelebration: (UUID) -> Bool = { _ in false }
    var onContinueCelebration: (UUID) -> Void = { _ in }
    var onRetryCelebration: () -> Void = {}

    var body: some View {
        switch state {
        case .loading:
            ProgressView("kidToday.loading").controlSize(.large)
        case let .loaded(content) where content.isEmpty:
            ContentUnavailableView(
                "kidToday.emptyTitle", systemImage: "sun.max.fill",
                description: Text("kidToday.emptyDescription")
            )
            .modifier(MangaPanel())
        case let .loaded(content):
            // 任务区必须作为一个布局子元素；否则错误和结果会被外层横屏HStack拆成两栏。
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                if celebrationVerificationFailed {
                    TodayCompletionVerificationErrorView(onRetry: onRetryCelebration)
                }
                if let summary = content.dailyCompletion {
                    if let event = celebrationEvent {
                        TodayCompletionCelebrationView(
                            event: event, reduceMotion: reduceMotion,
                            onClaimAnimation: onClaimCelebration, onContinue: onContinueCelebration
                        )
                        // 新完成ID重建局部视觉状态；旧ID重挂时共享claim仍拒绝再次播放。
                        .id(event.id)
                    } else {
                        KidTodayCompletionView(summary: summary)
                    }
                } else {
                    KidTodayLoadedView(
                        content: content, makeTimingPresentation: makeTimingPresentation, onSelectTask: onSelectTask)
                }
            }
        case .failed:
            ContentUnavailableView {
                Label("kidToday.errorTitle", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text("kidToday.errorDescription")
            } actions: {
                Button("kidToday.retry", systemImage: "arrow.clockwise", action: onRetry)
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .buttonStyle(MangaButtonStyle())
            }
            .modifier(MangaPanel())
        }
    }
}

#Preview("任务区 · 正常") {
    KidTodayTaskContent(
        state: .loaded(.preview), makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in },
        onRetry: {}
    ).padding()
}

#Preview("任务区 · 错误大字") {
    KidTodayTaskContent(
        state: .failed, makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }, onRetry: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("任务区 · 完成") {
    KidTodayTaskContent(
        state: .loaded(.previewCompleted), makeTimingPresentation: KidTaskTimingPresentation.preview,
        onSelectTask: { _ in }, onRetry: {}
    ).padding()
}

#Preview("任务区 · 空") {
    KidTodayTaskContent(
        state: .loaded(
            TodayScreenContent(
                recommendedTask: nil, remainingTasks: [], completedCount: 0, totalCount: 0, isAllCompleted: false)),
        makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }, onRetry: {}
    ).padding()
}

#Preview("任务区 · 新通关横屏") {
    KidTodayTaskContent(
        state: .loaded(.previewCompleted), makeTimingPresentation: KidTaskTimingPresentation.preview,
        onSelectTask: { _ in }, onRetry: {}, celebrationEvent: TodayCompletionCelebrationPreview.event
    )
    .padding().frame(width: 900)
}

#Preview("任务区 · 完成但庆祝失败MAX") {
    KidTodayTaskContent(
        state: .loaded(.previewCompleted), makeTimingPresentation: KidTaskTimingPresentation.preview,
        onSelectTask: { _ in }, onRetry: {}, celebrationVerificationFailed: true
    )
    .padding().frame(width: 900)
    .environment(\.dynamicTypeSize, .accessibility5)
}
