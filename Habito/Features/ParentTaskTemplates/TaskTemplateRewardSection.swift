import SwiftUI

/// 显式奖励输入与规则说明。原文由页面状态保留，解析和持久化不在 View 中执行。
struct TaskTemplateRewardSection: View {
    @Binding var input: TaskTemplateRewardInput
    let focus: FocusState<String?>.Binding
    let errorText: LocalizedStringKey?

    var body: some View {
        Section {
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
                Text("taskEditor.rewardHint")
                Text("taskEditor.autonomyHint")
            }
        }
    }
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
