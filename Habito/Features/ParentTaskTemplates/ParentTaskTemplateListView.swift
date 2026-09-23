import SwiftUI

/// 家长中心的任务模板列表、空态和错误态。
struct ParentTaskTemplateListView: View {
    @State private var model: ParentTaskTemplateListViewModel
    let onCreate: () -> Void
    let onSelect: (UUID) -> Void

    init(
        model: ParentTaskTemplateListViewModel,
        onCreate: @escaping () -> Void,
        onSelect: @escaping (UUID) -> Void
    ) {
        _model = State(initialValue: model)
        self.onCreate = onCreate
        self.onSelect = onSelect
    }

    var body: some View {
        ParentTaskTemplateListContent(
            state: model.state,
            onCreate: onCreate,
            onSelect: onSelect,
            onRetry: model.load
        )
        .navigationTitle("parentTemplates.navigationTitle")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("parentTemplates.create", systemImage: "plus", action: onCreate)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentTemplateCreate)
            }
        }
        .accessibilityIdentifier(HabitoAccessibilityID.parentUnlocked)
        .task(model.load)
    }
}
