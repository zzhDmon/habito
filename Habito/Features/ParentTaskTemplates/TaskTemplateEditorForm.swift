import SwiftUI

/// 与持久化和导航解耦的任务表单，集中呈现字段和字段级校验反馈。
struct TaskTemplateEditorForm: View {
    @Binding var draft: TaskTemplateDraft
    @Binding var scheduledTime: Date
    let feedback: TaskTemplateEditorFeedback?
    let onToggleWeekday: (Weekday) -> Void

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

            Section {
                Toggle("taskEditor.enabled", isOn: $draft.isEnabled)
            }

            if feedbackLocation == .general {
                Section {
                    feedbackLabel(for: .general)
                }
            }
        }
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
            case .templateNotFound, .archivedTemplate, .missingRule, .unsupportedRecurrence:
                return .general
            }
        }
    }

    private func weekdayLabel(_ weekday: Weekday) -> LocalizedStringKey {
        LocalizedStringKey("weekday.\(weekday.rawValue)")
    }

    private func iconLabel(_ name: String) -> LocalizedStringKey {
        LocalizedStringKey("taskEditor.icon.\(name)")
    }

    private func colorLabel(_ token: String) -> LocalizedStringKey {
        LocalizedStringKey("taskEditor.color.\(token)")
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
        case general
    }
}

#Preview("新建任务 · 横屏") {
    @Previewable @State var draft = TaskTemplateDraft.new
    @Previewable @State var time = Date(timeIntervalSinceReferenceDate: 19 * 3_600 + 30 * 60)

    NavigationStack {
        TaskTemplateEditorForm(
            draft: $draft,
            scheduledTime: $time,
            feedback: nil,
            onToggleWeekday: { weekday in
                if draft.weekdays.contains(weekday) {
                    draft.weekdays.remove(weekday)
                } else {
                    draft.weekdays.insert(weekday)
                }
            }
        )
        .navigationTitle("taskEditor.createTitle")
    }
}

#Preview("新建任务 · 校验错误") {
    @Previewable @State var draft = TaskTemplateDraft.new
    @Previewable @State var time = Date(timeIntervalSinceReferenceDate: 19 * 3_600 + 30 * 60)

    TaskTemplateEditorForm(
        draft: $draft,
        scheduledTime: $time,
        feedback: .validation(.titleRequired),
        onToggleWeekday: { _ in }
    )
}

#Preview("新建任务 · 大号字体") {
    @Previewable @State var draft = TaskTemplateDraft.new
    @Previewable @State var time = Date(timeIntervalSinceReferenceDate: 19 * 3_600 + 30 * 60)

    TaskTemplateEditorForm(
        draft: $draft,
        scheduledTime: $time,
        feedback: nil,
        onToggleWeekday: { _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
