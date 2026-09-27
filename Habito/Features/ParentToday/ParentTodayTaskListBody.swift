import SwiftUI

/// 家长今日页的纯展示层，便于独立预览加载、空、正常和错误状态。
struct ParentTodayTaskListBody: View {
    let state: ParentTodayTaskListState
    let onReschedule: (TodayTaskItem) -> Void
    let onSkip: (UUID) -> Void
    let onRestore: (UUID) -> Void
    let onCorrectAsCompleted: (UUID) -> Void
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .loading:
            ProgressView("parentToday.loading")
        case let .loaded(content) where content.items.isEmpty:
            ContentUnavailableView(
                "parentToday.emptyTitle",
                systemImage: "calendar.badge.checkmark",
                description: Text("parentToday.emptyDescription")
            )
        case let .loaded(content):
            List(content.items) { item in
                ParentTodayTaskRow(
                    item: item,
                    onReschedule: { onReschedule(item) },
                    onSkip: { onSkip(item.id) },
                    onRestore: { onRestore(item.id) },
                    onCorrectAsCompleted: { onCorrectAsCompleted(item.id) }
                )
            }
            .listStyle(.insetGrouped)
        case .failed:
            ContentUnavailableView {
                Label("parentToday.errorTitle", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text("parentToday.errorDescription")
            } actions: {
                Button("parentToday.retry", action: onRetry)
            }
        }
    }
}

#Preview("今日管理 · 横屏") {
    NavigationStack {
        ParentTodayTaskListBody(
            state: .loaded(.preview),
            onReschedule: { _ in },
            onSkip: { _ in },
            onRestore: { _ in },
            onCorrectAsCompleted: { _ in },
            onRetry: {}
        )
        .navigationTitle("parentToday.navigationTitle")
    }
}

#Preview("今日管理 · 空态") {
    ParentTodayTaskListBody(
        state: .loaded(.previewEmpty),
        onReschedule: { _ in },
        onSkip: { _ in },
        onRestore: { _ in },
        onCorrectAsCompleted: { _ in },
        onRetry: {}
    )
}

#Preview("今日管理 · 大号字体") {
    ParentTodayTaskListBody(
        state: .loaded(.preview),
        onReschedule: { _ in },
        onSkip: { _ in },
        onRestore: { _ in },
        onCorrectAsCompleted: { _ in },
        onRetry: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

private extension ParentTodayTaskListContent {
    static var preview: ParentTodayTaskListContent {
        let date: LocalDate
        do {
            date = try LocalDate(dateKey: "2026-09-24")
        } catch {
            preconditionFailure("预览固定日期无效")
        }
        return ParentTodayTaskListContent(
            date: date,
            items: [
                TodayTaskItem(
                    id: UUID(),
                    date: date,
                    scheduledAt: Date(timeIntervalSince1970: 1_790_226_600),
                    title: "阅读 15 分钟",
                    iconName: "book.fill",
                    colorToken: "reading",
                    targetDurationSeconds: 900,
                    status: .pending,
                    origin: .generated(templateRevision: 1),
                    activeSessionState: nil,
                    activeDurationSeconds: 0,
                    completion: nil
                )
            ]
        )
    }

    static var previewEmpty: ParentTodayTaskListContent {
        var value = preview
        value = ParentTodayTaskListContent(date: value.date, items: [])
        return value
    }
}
