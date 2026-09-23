import SwiftUI

/// 孩子打开 App 后看到的今日页基础结构。
struct KidTodayView: View {
    let state: TodayViewState
    let onSelectTask: (KidTaskNavigationItem) -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("kidToday.loading")
                    .controlSize(.large)
            case let .loaded(content) where content.isEmpty:
                ContentUnavailableView(
                    "kidToday.emptyTitle",
                    systemImage: "sun.max.fill",
                    description: Text("kidToday.emptyDescription")
                )
            case let .loaded(content) where content.isAllCompleted:
                ContentUnavailableView(
                    "kidToday.completedTitle",
                    systemImage: HabitoDesign.Symbol.completed,
                    description: Text("kidToday.completedDescription")
                )
            case let .loaded(content):
                KidTodayLoadedView(content: content, onSelectTask: onSelectTask)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(HabitoAccessibilityID.todayScreen)
        .navigationTitle("kidToday.navigationTitle")
        .background(.background)
    }
}

#Preview("今日 · iPad 横屏") {
    NavigationStack {
        KidTodayView(state: .loaded(.preview), onSelectTask: { _ in }, onRetry: {})
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 空态") {
    NavigationStack {
        KidTodayView(
            state: .loaded(
                TodayScreenContent(
                    recommendedTask: nil,
                    remainingTasks: [],
                    completedCount: 0,
                    totalCount: 0,
                    isAllCompleted: false
                )
            ),
            onSelectTask: { _ in },
            onRetry: {}
        )
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 全部完成") {
    NavigationStack {
        KidTodayView(
            state: .loaded(
                TodayScreenContent(
                    recommendedTask: nil,
                    remainingTasks: [.previewCompleted],
                    completedCount: 1,
                    totalCount: 1,
                    isAllCompleted: true
                )
            ),
            onSelectTask: { _ in },
            onRetry: {}
        )
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 昨日任务进行中") {
    NavigationStack {
        KidTodayView(
            state: .loaded(.previewCarryOver),
            onSelectTask: { _ in },
            onRetry: {}
        )
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 数据错误") {
    NavigationStack {
        KidTodayView(state: .failed, onSelectTask: { _ in }, onRetry: {})
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 辅助功能字号") {
    NavigationStack {
        KidTodayView(state: .loaded(.preview), onSelectTask: { _ in }, onRetry: {})
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
