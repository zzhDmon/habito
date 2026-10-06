import SwiftUI

/// 家长可选时间输入，只转发草稿绑定；未启用时不展示或保存假时间。
///
/// 主 actor 页面模型拥有分钟映射；此组件不触碰持久化、通知或奖励。
struct TaskTemplateTimeSection: View {
    @Binding var isPlannedTimeEnabled: Bool
    @Binding var plannedTime: Date
    @Binding var isDeadlineTimeEnabled: Bool
    @Binding var deadlineTime: Date

    var body: some View {
        Section {
            // Switch 的 AX 整行与小滑钮不同；真实 Button 保留按钮角色，并让整行 44 pt 真正可点。
            Button(action: togglePlannedTime) {
                Label(
                    "taskEditor.setPlannedTime", systemImage: isPlannedTimeEnabled ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("taskEditor.setPlannedTime")
            .accessibilityValue(isPlannedTimeEnabled ? "taskEditor.selected" : "taskEditor.notSelected")
            .accessibilityIdentifier(HabitoAccessibilityID.taskEditorPlannedEnabled)
            if isPlannedTimeEnabled {
                DatePicker("taskEditor.plannedTime", selection: $plannedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .accessibilityLabel("taskEditor.plannedTime")
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskEditorPlannedTime)
            }
            Button(action: toggleDeadlineTime) {
                Label(
                    "taskEditor.setDeadlineTime",
                    systemImage: isDeadlineTimeEnabled ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("taskEditor.setDeadlineTime")
            .accessibilityValue(isDeadlineTimeEnabled ? "taskEditor.selected" : "taskEditor.notSelected")
            .accessibilityIdentifier(HabitoAccessibilityID.taskEditorDeadlineEnabled)
            if isDeadlineTimeEnabled {
                DatePicker("taskEditor.deadlineTime", selection: $deadlineTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .accessibilityLabel("taskEditor.deadlineTime")
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskEditorDeadlineTime)
            }
        } header: {
            Text("taskEditor.optionalTimesSection")
        } footer: {
            Text("taskEditor.optionalTimesHint")
        }
    }

    /// 只转发启用/关闭意图；候选时分和 nil 清空语义仍由页面模型处理。
    private func togglePlannedTime() { isPlannedTimeEnabled.toggle() }

    private func toggleDeadlineTime() { isDeadlineTimeEnabled.toggle() }
}

#Preview("可空时间 · 未设置") {
    @Previewable @State var planEnabled = false
    @Previewable @State var deadlineEnabled = false
    @Previewable @State var plan = Date(timeIntervalSinceReferenceDate: 0)
    @Previewable @State var deadline = Date(timeIntervalSinceReferenceDate: 3600)
    Form {
        TaskTemplateTimeSection(
            isPlannedTimeEnabled: $planEnabled, plannedTime: $plan,
            isDeadlineTimeEnabled: $deadlineEnabled, deadlineTime: $deadline)
    }
}

#Preview("可空时间 · 已设置 · 横屏") {
    @Previewable @State var planEnabled = true
    @Previewable @State var deadlineEnabled = true
    @Previewable @State var plan = Date(timeIntervalSinceReferenceDate: 0)
    @Previewable @State var deadline = Date(timeIntervalSinceReferenceDate: 3600)
    Form {
        TaskTemplateTimeSection(
            isPlannedTimeEnabled: $planEnabled, plannedTime: $plan,
            isDeadlineTimeEnabled: $deadlineEnabled, deadlineTime: $deadline)
    }
}

#Preview("可空时间 · 已设置 · 最大字号") {
    @Previewable @State var planEnabled = true
    @Previewable @State var deadlineEnabled = true
    @Previewable @State var plan = Date(timeIntervalSinceReferenceDate: 0)
    @Previewable @State var deadline = Date(timeIntervalSinceReferenceDate: 3600)
    Form {
        TaskTemplateTimeSection(
            isPlannedTimeEnabled: $planEnabled, plannedTime: $plan,
            isDeadlineTimeEnabled: $deadlineEnabled, deadlineTime: $deadline)
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
