import SwiftUI

/// 今日任务的独立状态区域，不以资产加载是否成功决定任务能否查看。
struct KidTodayTaskContent: View {
    let state: TodayViewState
    let makeTimingPresentation: @MainActor (KidTaskNavigationItem) -> KidTaskTimingPresentation
    let onSelectTask: (KidTaskNavigationItem) -> Void
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .loading:
            ProgressView("kidToday.loading").controlSize(.large)
        case let .loaded(content) where content.isEmpty:
            ContentUnavailableView(
                "kidToday.emptyTitle", systemImage: "sun.max.fill",
                description: Text("kidToday.emptyDescription"))
        case let .loaded(content) where content.isAllCompleted:
            ContentUnavailableView(
                "kidToday.completedTitle", systemImage: HabitoDesign.Symbol.completed,
                description: Text("kidToday.completedDescription"))
        case let .loaded(content):
            KidTodayLoadedView(
                content: content, makeTimingPresentation: makeTimingPresentation, onSelectTask: onSelectTask)
        case .failed:
            ContentUnavailableView {
                Label("kidToday.errorTitle", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text("kidToday.errorDescription")
            } actions: {
                Button("kidToday.retry", systemImage: "arrow.clockwise", action: onRetry)
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            }
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
