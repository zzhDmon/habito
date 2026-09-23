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
                    onToggleWeekday: model.toggle,
                    onDisable: { model.prepareLifecycleAction(.disable) },
                    onEnable: { model.prepareLifecycleAction(.enable) },
                    onArchive: { model.prepareLifecycleAction(.archive) }
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
        .alert(
            lifecycleTitle,
            isPresented: lifecycleConfirmationBinding,
            presenting: model.lifecycleImpact
        ) { impact in
            Button(
                lifecycleConfirmationLabel(for: impact.action),
                role: impact.action == .archive ? .destructive : nil,
                action: confirmLifecycleAction
            )
            .accessibilityIdentifier(HabitoAccessibilityID.taskLifecycleConfirm)
            Button("taskLifecycle.cancel", role: .cancel, action: model.cancelLifecycleAction)
                .accessibilityIdentifier(HabitoAccessibilityID.taskLifecycleCancel)
        } message: { impact in
            lifecycleMessage(for: impact)
        }
    }

    private func save() {
        guard model.save() else { return }
        onSaved()
        dismiss()
    }

    private var lifecycleConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.lifecycleImpact != nil },
            set: { isPresented in
                if !isPresented { model.cancelLifecycleAction() }
            }
        )
    }

    private var lifecycleTitle: LocalizedStringKey {
        switch model.lifecycleImpact?.action {
        case .disable: "taskLifecycle.disableTitle"
        case .enable: "taskLifecycle.enableTitle"
        case .archive: "taskLifecycle.archiveTitle"
        case nil: "taskLifecycle.disableTitle"
        }
    }

    private func lifecycleConfirmationLabel(
        for action: TaskTemplateLifecycleAction
    ) -> LocalizedStringKey {
        switch action {
        case .disable: "taskLifecycle.disableConfirm"
        case .enable: "taskLifecycle.enableConfirm"
        case .archive: "taskLifecycle.archiveConfirm"
        }
    }

    private func lifecycleMessage(for impact: TaskTemplateLifecycleImpact) -> Text {
        if impact.action == .enable {
            return Text("taskLifecycle.enableMessage")
        }
        return Text("taskLifecycle.removePrefix")
            + Text(verbatim: " \(impact.removableOccurrenceCount) ")
            + Text("taskLifecycle.removeSuffix")
            + Text(verbatim: " \(impact.preservedOccurrenceCount) ")
            + Text("taskLifecycle.preserveSuffix")
    }

    private func confirmLifecycleAction() {
        guard let action = model.confirmLifecycleAction() else { return }
        onSaved()
        if action == .archive { dismiss() }
    }
}
