import SwiftUI

/// 统一主要动作按钮的语义字号与点击面积，调用方决定样式，不在按钮中编排业务。
struct TaskSessionActionButton: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(titleKey, systemImage: systemImage)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
        }
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("提交按钮 · 大字") {
    TaskSessionActionButton(
        titleKey: "taskSession.submitForReview", systemImage: "paperplane.fill",
        identifier: HabitoAccessibilityID.submitButton, action: {}
    )
    .buttonStyle(.borderedProminent)
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}
