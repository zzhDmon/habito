import SwiftUI

/// 标签和金额在上下两行，避免辅助字号下横排标签挤掉可编辑区域。
struct TaskTemplateRewardField: View {
    let title: LocalizedStringKey
    @Binding var value: String
    let focus: FocusState<String?>.Binding
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
            Text(title)
            TextField(title, text: $value)
                .focused(focus, equals: identifier)
                // 使用可缩放的语义数字字号，保持原生输入区域，不叠加额外焦点控件。
                .font(.largeTitle)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                .contentShape(Rectangle())
                .accessibilityLabel(Text(title))
                .accessibilityHint("taskEditor.rewardInputHint")
                .accessibilityIdentifier(identifier)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier + ".row")
    }

}

#Preview("零奖励 · 最大字号") {
    @Previewable @State var input = TaskTemplateRewardInput(draft: .new)
    @Previewable @FocusState var focus: String?
    Form {
        TaskTemplateRewardSection(input: $input, focus: $focus, errorText: nil)
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
