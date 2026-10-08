import SwiftUI

/// 创建或编辑按星期重复任务的家长表单。
struct TaskTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: TaskTemplateEditorViewModel
    @State private var isNotificationWarningPresented = false
    // FocusState 随当前页面生灭并由 UI 主 actor 管理；保存前结束编辑，让错误提示不被键盘遮挡。
    @FocusState private var focusedReward: String?
    let onSaved: () -> Void

    init(model: TaskTemplateEditorViewModel, onSaved: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var model = model

        // Form 与保存栏占据独立的布局空间。弹层收起键盘或改变高度时，
        // 不依赖 Form 对 safeAreaInset 的缓存，避免按钮留在表单中部遮住奖励字段。
        VStack(spacing: 0) {
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
                        rewardInput: $model.rewardInput,
                        rewardFocus: $focusedReward,
                        scheduledTime: $model.scheduledTime,
                        isPlannedTimeEnabled: $model.isPlannedTimeEnabled,
                        plannedTime: $model.plannedTime,
                        isDeadlineTimeEnabled: $model.isDeadlineTimeEnabled,
                        deadlineTime: $model.deadlineTime,
                        feedback: model.feedback,
                        onToggleWeekday: model.toggle,
                        onDisable: { model.prepareLifecycleAction(.disable) },
                        onEnable: { model.prepareLifecycleAction(.enable) },
                        onArchive: { model.prepareLifecycleAction(.archive) },
                        onApplyPreset: model.applyLearningPreset
                    )
                    .environment(\.calendar, model.timeInputCalendar)
                    .environment(\.timeZone, model.timeInputCalendar.timeZone)
                    .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskEditorScreen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TaskTemplateEditorSaveBar(
                isDisabled: model.isLoading || model.isSaving || model.hasLoadFailure,
                onSave: save
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle(model.isCreating ? "taskEditor.createTitle" : "taskEditor.editTitle")
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
        .alert("notification.permissionWarningTitle", isPresented: $isNotificationWarningPresented) {
            Button("notification.permissionWarningConfirm", action: finishSaving)
        } message: {
            Text("notification.permissionWarningMessage")
        }
    }

    private func save() {
        focusedReward = nil
        Task {
            switch await model.save() {
            case .failed:
                break
            case .saved:
                finishSaving()
            case .savedWithNotificationWarning:
                isNotificationWarningPresented = true
            }
        }
    }

    private func finishSaving() {
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
        let removePrefix = Text("taskLifecycle.removePrefix")
        let removableCount = Text(verbatim: " \(impact.removableOccurrenceCount) ")
        let removeSuffix = Text("taskLifecycle.removeSuffix")
        let preservedCount = Text(verbatim: " \(impact.preservedOccurrenceCount) ")
        let preserveSuffix = Text("taskLifecycle.preserveSuffix")
        return Text(
            "\(removePrefix)\(removableCount)\(removeSuffix)\(preservedCount)\(preserveSuffix)"
        )
    }

    private func confirmLifecycleAction() {
        guard let action = model.confirmLifecycleAction() else { return }
        onSaved()
        if action == .archive { dismiss() }
    }
}
