import SwiftUI

/// 创建或编辑按星期重复任务的家长表单。
struct TaskTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: TaskTemplateEditorViewModel
    let onSaved: () -> Void

    init(model: TaskTemplateEditorViewModel, onSaved: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if model.isLoading {
                ProgressView("taskEditor.loading")
            } else if model.hasLoadFailure {
                ContentUnavailableView(
                    "taskEditor.errorLoadTitle",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("taskEditor.errorLoad")
                )
            } else {
                TaskTemplateEditorForm(
                    draft: $model.draft,
                    scheduledTime: $model.scheduledTime,
                    feedback: model.feedback,
                    onToggleWeekday: model.toggle
                )
                .accessibilityIdentifier(HabitoAccessibilityID.taskEditorScreen)
            }
        }
        .navigationTitle(model.isCreating ? "taskEditor.createTitle" : "taskEditor.editTitle")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("taskEditor.save", action: save)
                    .disabled(model.isLoading || model.isSaving)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskEditorSave)
            }
        }
        .task(model.load)
    }

    private func save() {
        guard model.save() else { return }
        onSaved()
        dismiss()
    }
}
