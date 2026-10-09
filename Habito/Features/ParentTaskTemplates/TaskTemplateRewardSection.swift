import SwiftUI

/// 显式奖励输入与规则说明。原文由页面状态保留，解析和持久化不在 View 中执行。
struct TaskTemplateRewardSection: View {
    @State private var isExpanded = false
    @Binding var input: TaskTemplateRewardInput
    let focus: FocusState<String?>.Binding
    let errorText: LocalizedStringKey?

    var body: some View {
        Section {
            // 展开按钮与输入分属Form行；避免DisclosureGroup把整组输入合并为同一点击区域。
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
                    Label("taskEditor.rewardSection", systemImage: showsFields ? "chevron.up" : "chevron.down")
                    Text("taskEditor.rewardSummary \(input.xp) \(input.baseCoins) \(input.autonomyCoins)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsFields ? "taskEditor.expanded" : "taskEditor.collapsed")
            .accessibilityIdentifier("parent.templates.editor.reward-expand")
            if showsFields {
                TaskTemplateRewardField(
                    title: "taskEditor.xp", value: $input.xp,
                    focus: focus,
                    identifier: HabitoAccessibilityID.taskEditorXP,
                    amounts: TaskRewardPresets.xp
                )
                TaskTemplateRewardField(
                    title: "taskEditor.baseCoins", value: $input.baseCoins,
                    focus: focus,
                    identifier: HabitoAccessibilityID.taskEditorBaseCoins,
                    amounts: TaskRewardPresets.coins
                )
                TaskTemplateRewardField(
                    title: "taskEditor.autonomyCoins", value: $input.autonomyCoins,
                    focus: focus,
                    identifier: HabitoAccessibilityID.taskEditorAutonomyCoins,
                    amounts: TaskRewardPresets.autonomyCoins
                )
            }

        } header: {
            Text("taskEditor.rewardSection")
        } footer: {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(HabitoAccessibilityID.taskEditorRewardError)
                }
                if showsFields {
                    Text("taskEditor.rewardHint")
                    Text("taskEditor.autonomyHint")
                }
            }
        }
        .onChange(of: errorText != nil, initial: true) { _, hasError in
            if hasError { isExpanded = true }
        }
    }
    private var showsFields: Bool { isExpanded || errorText != nil }
    private func toggleExpanded() { isExpanded.toggle() }

}

#Preview("显式奖励 · 横屏") {
    @Previewable @State var input = TaskTemplateRewardInput(draft: .new)
    @Previewable @FocusState var focus: String?
    Form { TaskTemplateRewardSection(input: $input, focus: $focus, errorText: nil) }
}

#Preview("错误输入 · 最大字号") {
    @Previewable @FocusState var focus: String?
    @Previewable @State var input = {
        var value = TaskTemplateRewardInput(draft: .new)
        value.xp = "-1"
        return value
    }()
    Form { TaskTemplateRewardSection(input: $input, focus: $focus, errorText: "taskEditor.errorRewardInput") }
        .environment(\.dynamicTypeSize, .accessibility5)
}
