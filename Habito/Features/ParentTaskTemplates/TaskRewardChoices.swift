import SwiftUI

/// 数值按钮与自定义输入共享同一原文；选择不会触发保存或直接发奖。
struct TaskRewardChoices: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var value: String
    let amounts: [Int]
    let title: LocalizedStringKey
    let identifier: String
    let focus: FocusState<String?>.Binding

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 80))]) {
            ForEach(amounts, id: \.self) { amount in
                Button {
                    choose(amount)
                } label: {
                    Label(String(amount), systemImage: Int(value) == amount ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                // 原生自适应 Label 在窄栏可能只留图标；金额必须始终可见。
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .accessibilityLabel(Text(title) + Text(verbatim: " \(amount)"))
                .accessibilityAddTraits(Int(value) == amount ? .isSelected : [])
                .accessibilityIdentifier(identifier + ".preset." + String(amount))
            }
        }
    }

    private func choose(_ amount: Int) {
        focus.wrappedValue = nil
        value = String(amount)
    }
}

#Preview("奖励按钮 · 大字号") {
    @Previewable @State var value = "10"
    @Previewable @FocusState var focus: String?
    TaskRewardChoices(
        value: $value, amounts: TaskRewardPresets.xp, title: "taskEditor.xp", identifier: "preview", focus: $focus
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
