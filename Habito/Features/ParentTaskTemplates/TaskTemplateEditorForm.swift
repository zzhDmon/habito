import SwiftUI

/// 与持久化和导航解耦的任务表单，集中呈现字段和字段级校验反馈。
struct TaskTemplateEditorForm: View {
    @Binding var draft: TaskTemplateDraft
    @Binding var rewardInput: TaskTemplateRewardInput
    let rewardFocus: FocusState<String?>.Binding
    @Binding var scheduledTime: Date
    @Binding var isPlannedTimeEnabled: Bool
    @Binding var plannedTime: Date
    @Binding var isDeadlineTimeEnabled: Bool
    @Binding var deadlineTime: Date
    let feedback: TaskTemplateEditorFeedback?
    let onToggleWeekday: (Weekday) -> Void
    let onDisable: () -> Void
    let onEnable: () -> Void
    let onArchive: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("taskEditor.title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskEditorTitle)
                Picker("taskEditor.icon", selection: $draft.iconName) {
                    ForEach(TaskTemplateDraft.allowedIconNames, id: \.self) { name in
                        Label(iconLabel(name), systemImage: name).tag(name)
                    }
                }
                Picker("taskEditor.color", selection: $draft.colorToken) {
                    ForEach(TaskTemplateDraft.allowedColorTokens, id: \.self) { token in
                        Text(colorLabel(token)).tag(token)
                    }
                }
            } header: {
                Text("taskEditor.basicSection")
            } footer: {
                feedbackLabel(for: .basic)
            }

            Section {
                DatePicker(
                    "taskEditor.time",
                    selection: $scheduledTime,
                    displayedComponents: .hourAndMinute
                )
                // compact 时间按钮在最低系统实际 AX 高度仅 36 pt；原生滚轮保证可操作面积和精确读屏。
                .datePickerStyle(.wheel)
                .accessibilityLabel("taskEditor.time")
                .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.taskEditorReminderTime)
                TextField(
                    "taskEditor.durationMinutes",
                    value: $draft.targetDurationMinutes,
                    format: .number
                )
                .keyboardType(.numberPad)
                .accessibilityIdentifier(HabitoAccessibilityID.taskEditorDuration)
            } header: {
                Text("taskEditor.scheduleSection")
            } footer: {
                feedbackLabel(for: .schedule)
            }

            TaskTemplateTimeSection(
                isPlannedTimeEnabled: $isPlannedTimeEnabled, plannedTime: $plannedTime,
                isDeadlineTimeEnabled: $isDeadlineTimeEnabled, deadlineTime: $deadlineTime)

            Section {
                ForEach(Weekday.allCases, id: \.self) { weekday in
                    Button {
                        onToggleWeekday(weekday)
                    } label: {
                        Label(
                            weekdayLabel(weekday),
                            systemImage: draft.weekdays.contains(weekday)
                                ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    .foregroundStyle(.primary)
                    .accessibilityValue(
                        draft.weekdays.contains(weekday)
                            ? "taskEditor.selected" : "taskEditor.notSelected"
                    )
                }
            } header: {
                Text("taskEditor.weekdaysSection")
            } footer: {
                if feedbackLocation == .weekdays {
                    feedbackLabel(for: .weekdays)
                } else {
                    Text("taskEditor.weekdaysHint")
                }
            }

            if draft.templateID == nil {
                Section {
                    Toggle("taskEditor.enabled", isOn: $draft.isEnabled)
                }
            } else {
                Section("taskLifecycle.section") {
                    if draft.isEnabled {
                        Button("taskLifecycle.disable", action: onDisable)
                            .accessibilityIdentifier(HabitoAccessibilityID.taskLifecycleDisable)
                    } else {
                        Button("taskLifecycle.enable", action: onEnable)
                            .accessibilityIdentifier(HabitoAccessibilityID.taskLifecycleEnable)
                    }
                    Button("taskLifecycle.archive", role: .destructive, action: onArchive)
                        .accessibilityIdentifier(HabitoAccessibilityID.taskLifecycleArchive)
                }
            }

            TaskTemplateConfigurationSection(draft: $draft)
            TaskTemplateRewardSection(
                input: $rewardInput,
                focus: rewardFocus,
                errorText: feedbackLocation == .reward ? feedback.map(feedbackText) : nil
            )

            if feedbackLocation == .general {
                Section {
                    feedbackLabel(for: .general)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func feedbackLabel(for location: FeedbackLocation) -> some View {
        if feedbackLocation == location, let feedback {
            Label(feedbackText(feedback), systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var feedbackLocation: FeedbackLocation? {
        guard let feedback else { return nil }
        switch feedback {
        case .loadFailure, .storageFailure:
            return .general
        case let .validation(error):
            switch error {
            case .titleRequired, .titleTooLong, .unsupportedIcon, .unsupportedColor:
                return .basic
            case .invalidDuration, .invalidTime:
                return .schedule
            case .noWeekdays:
                return .weekdays
            case .invalidReward, .invalidRewardInput, .rewardOverflow:
                return .reward
            case .templateNotFound, .archivedTemplate, .missingRule, .unsupportedRecurrence,
                .revisionOverflow, .invalidStoredRevision, .pendingContextChanges:
                return .general
            }
        }
    }

    private func weekdayLabel(_ weekday: Weekday) -> LocalizedStringKey {
        LocalizedStringKey("weekday." + String(weekday.rawValue))
    }

    private func iconLabel(_ name: String) -> LocalizedStringKey {
        LocalizedStringKey("taskEditor.icon." + name)
    }

    private func colorLabel(_ token: String) -> LocalizedStringKey {
        LocalizedStringKey("taskEditor.color." + token)
    }

    private func feedbackText(_ feedback: TaskTemplateEditorFeedback) -> LocalizedStringKey {
        switch feedback {
        case .loadFailure: "taskEditor.errorLoad"
        case .storageFailure: "taskEditor.errorSave"
        case let .validation(error): validationText(error)
        }
    }

    private func validationText(_ error: TaskTemplateEditorError) -> LocalizedStringKey {
        switch error {
        case .titleRequired: "taskEditor.errorTitleRequired"
        case .titleTooLong: "taskEditor.errorTitleTooLong"
        case .invalidDuration: "taskEditor.errorDuration"
        case .invalidTime: "taskEditor.errorTime"
        case .noWeekdays: "taskEditor.errorWeekdays"
        case .unsupportedIcon, .unsupportedColor: "taskEditor.errorOption"
        case .invalidReward: "taskEditor.errorReward"
        case .invalidRewardInput: "taskEditor.errorRewardInput"
        case .rewardOverflow: "taskEditor.errorRewardOverflow"
        case .revisionOverflow, .invalidStoredRevision: "taskEditor.errorRevision"
        case .pendingContextChanges: "taskEditor.errorPendingChanges"
        case .templateNotFound, .archivedTemplate, .missingRule, .unsupportedRecurrence:
            "taskEditor.errorLoad"
        }
    }
}

private extension TaskTemplateEditorForm {
    enum FeedbackLocation {
        case basic
        case schedule
        case weekdays
        case reward
        case general
    }
}

#Preview("新建任务 · 横屏") {
    @Previewable @State var plannedEnabled = false
    @Previewable @State var deadlineEnabled = false
    @Previewable @State var planTime = Date(timeIntervalSinceReferenceDate: 0)
    @Previewable @State var deadlineTime = Date(timeIntervalSinceReferenceDate: 3600)
    @Previewable @State var draft = TaskTemplateDraft.new
    @Previewable @State var rewardInput = TaskTemplateRewardInput(draft: .new)
    @Previewable @FocusState var rewardFocus: String?
    @Previewable @State var time = Date(timeIntervalSinceReferenceDate: 19 * 3_600 + 30 * 60)

    NavigationStack {
        TaskTemplateEditorForm(
            draft: $draft,
            rewardInput: $rewardInput,
            rewardFocus: $rewardFocus,
            scheduledTime: $time,
            isPlannedTimeEnabled: $plannedEnabled, plannedTime: $planTime,
            isDeadlineTimeEnabled: $deadlineEnabled, deadlineTime: $deadlineTime,
            feedback: nil,
            onToggleWeekday: { weekday in
                if draft.weekdays.contains(weekday) {
                    draft.weekdays.remove(weekday)
                } else {
                    draft.weekdays.insert(weekday)
                }
            },
            onDisable: {},
            onEnable: {},
            onArchive: {}
        )
        .navigationTitle("taskEditor.createTitle")
    }
}

#Preview("新建任务 · 校验错误") {
    @Previewable @State var plannedEnabled = false
    @Previewable @State var deadlineEnabled = false
    @Previewable @State var planTime = Date(timeIntervalSinceReferenceDate: 0)
    @Previewable @State var deadlineTime = Date(timeIntervalSinceReferenceDate: 3600)
    @Previewable @State var draft = TaskTemplateDraft.new
    @Previewable @State var rewardInput = TaskTemplateRewardInput(draft: .new)
    @Previewable @FocusState var rewardFocus: String?
    @Previewable @State var time = Date(timeIntervalSinceReferenceDate: 19 * 3_600 + 30 * 60)

    NavigationStack {
        TaskTemplateEditorForm(
            draft: $draft,
            rewardInput: $rewardInput,
            rewardFocus: $rewardFocus,
            scheduledTime: $time,
            isPlannedTimeEnabled: $plannedEnabled, plannedTime: $planTime,
            isDeadlineTimeEnabled: $deadlineEnabled, deadlineTime: $deadlineTime,
            feedback: .validation(.titleRequired),
            onToggleWeekday: { _ in },
            onDisable: {},
            onEnable: {},
            onArchive: {}
        )
    }
}

#Preview("新建任务 · 大号字体") {
    @Previewable @State var plannedEnabled = false
    @Previewable @State var deadlineEnabled = false
    @Previewable @State var planTime = Date(timeIntervalSinceReferenceDate: 0)
    @Previewable @State var deadlineTime = Date(timeIntervalSinceReferenceDate: 3600)
    @Previewable @State var draft = TaskTemplateDraft.new
    @Previewable @State var rewardInput = TaskTemplateRewardInput(draft: .new)
    @Previewable @FocusState var rewardFocus: String?
    @Previewable @State var time = Date(timeIntervalSinceReferenceDate: 19 * 3_600 + 30 * 60)

    NavigationStack {
        TaskTemplateEditorForm(
            draft: $draft,
            rewardInput: $rewardInput,
            rewardFocus: $rewardFocus,
            scheduledTime: $time,
            isPlannedTimeEnabled: $plannedEnabled, plannedTime: $planTime,
            isDeadlineTimeEnabled: $deadlineEnabled, deadlineTime: $deadlineTime,
            feedback: nil,
            onToggleWeekday: { _ in },
            onDisable: {},
            onEnable: {},
            onArchive: {}
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("编辑已停用任务 · 横屏") {
    @Previewable @State var plannedEnabled = false
    @Previewable @State var deadlineEnabled = false
    @Previewable @State var planTime = Date(timeIntervalSinceReferenceDate: 0)
    @Previewable @State var deadlineTime = Date(timeIntervalSinceReferenceDate: 3600)
    @Previewable @State var rewardInput = TaskTemplateRewardInput(draft: .new)
    @Previewable @FocusState var rewardFocus: String?
    @Previewable @State var draft = TaskTemplateDraft(
        templateID: UUID(),
        title: "阅读 15 分钟",
        iconName: "book.fill",
        colorToken: "reading",
        timeOfDayMinutes: 19 * 60 + 30,
        targetDurationMinutes: 15,
        weekdays: Set(Weekday.allCases),
        isEnabled: false
    )
    @Previewable @State var time = Date(timeIntervalSinceReferenceDate: 19 * 3_600 + 30 * 60)

    NavigationStack {
        TaskTemplateEditorForm(
            draft: $draft,
            rewardInput: $rewardInput,
            rewardFocus: $rewardFocus,
            scheduledTime: $time,
            isPlannedTimeEnabled: $plannedEnabled, plannedTime: $planTime,
            isDeadlineTimeEnabled: $deadlineEnabled, deadlineTime: $deadlineTime,
            feedback: nil,
            onToggleWeekday: { _ in },
            onDisable: {},
            onEnable: {},
            onArchive: {}
        )
        .navigationTitle("taskEditor.editTitle")
    }
}
