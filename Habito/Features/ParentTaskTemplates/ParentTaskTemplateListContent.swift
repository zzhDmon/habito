import SwiftUI

/// 模板列表的纯展示层，便于覆盖空态、错误态与不同动态字体尺寸。
struct ParentTaskTemplateListContent: View {
    let state: ParentTaskTemplateListState
    let onCreate: () -> Void
    let onSelect: (UUID) -> Void
    let onRetry: () -> Void
    var showsSetupGuide = false
    var setupHasTask = false
    var onCheckReminders: () -> Void = {}

    var body: some View {
        switch state {
        case .loading:
            ProgressView("parentTemplates.loading")
        case let .loaded(items) where items.isEmpty:
            if showsSetupGuide {
                ScrollView {
                    ParentSetupGuide(hasTask: setupHasTask, onCreate: onCreate, onCheckReminders: onCheckReminders)
                }
                .accessibilityIdentifier("parent.setup.scroll")
            } else {
                ContentUnavailableView {
                    Label("parentTemplates.emptyTitle", systemImage: "checklist")
                } description: {
                    Text("parentTemplates.emptyDescription")
                } actions: {
                    Button("parentTemplates.create", action: onCreate)
                        .buttonStyle(MangaButtonStyle())
                }
            }
        case let .loaded(items):
            List {
                if showsSetupGuide {
                    ParentSetupGuide(hasTask: setupHasTask, onCreate: onCreate, onCheckReminders: onCheckReminders)
                }
                ForEach(items) { item in
                    ParentTaskTemplateRow(item: item) {
                        onSelect(item.id)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("parent.templates.list")
        case .failed:
            ContentUnavailableView {
                Label("parentTemplates.errorTitle", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text("parentTemplates.errorDescription")
            } actions: {
                Button("parentTemplates.retry", action: onRetry)
            }
        }
    }
}

#Preview("模板列表 · 横屏") {
    NavigationStack {
        ParentTaskTemplateListContent(
            state: .loaded([.previewEnabled, .previewDisabled]),
            onCreate: {},
            onSelect: { _ in },
            onRetry: {}
        )
        .navigationTitle("parentTemplates.navigationTitle")
    }
}

#Preview("模板列表 · 空态") {
    ParentTaskTemplateListContent(
        state: .loaded([]),
        onCreate: {},
        onSelect: { _ in },
        onRetry: {}
    )
}

#Preview("模板列表 · 错误") {
    ParentTaskTemplateListContent(
        state: .failed,
        onCreate: {},
        onSelect: { _ in },
        onRetry: {}
    )
}

#Preview("模板列表 · 大号字体") {
    ParentTaskTemplateListContent(
        state: .loaded([.previewEnabled, .previewDisabled]),
        onCreate: {},
        onSelect: { _ in },
        onRetry: {}
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

private extension ParentTaskTemplateListItem {
    static let previewEnabled = ParentTaskTemplateListItem(
        id: UUID(),
        title: "阅读 15 分钟",
        iconName: "book.fill",
        targetDurationSeconds: 900,
        lifecycleState: .active,
        nextScheduledAt: Date(timeIntervalSince1970: 1_790_150_400),
        updatedAt: Date(timeIntervalSince1970: 1_790_064_000)
    )

    static let previewDisabled = ParentTaskTemplateListItem(
        id: UUID(),
        title: "练字",
        iconName: "pencil.line",
        targetDurationSeconds: 1_200,
        lifecycleState: .disabled,
        nextScheduledAt: nil,
        updatedAt: Date(timeIntervalSince1970: 1_789_977_600)
    )
}
