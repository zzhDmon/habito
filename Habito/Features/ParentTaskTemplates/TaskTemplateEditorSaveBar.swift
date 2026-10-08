import SwiftUI

/// 固定在编辑页安全区内的保存入口，不随长表单滚出屏幕。
///
/// 工具栏在新系统会压缩按钮的实际无障碍区域；独立原生按钮让触控区域与大字号一起增长。
/// 此组件只转发保存意图，校验和持久化仍由原编辑用例负责。
struct TaskTemplateEditorSaveBar: View {
    let isDisabled: Bool
    let onSave: () -> Void

    var body: some View {
        VStack {
            Button(action: onSave) {
                Text("taskEditor.save")
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
            }
            .buttonStyle(MangaButtonStyle())
            .disabled(isDisabled)
            .accessibilityIdentifier(HabitoAccessibilityID.taskEditorSave)
        }
        .padding(.horizontal, HabitoDesign.Spacing.medium)
        .padding(.vertical, HabitoDesign.Spacing.small)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.taskEditorSaveBar)
    }
}

#Preview("保存") {
    TaskTemplateEditorSaveBar(isDisabled: false, onSave: {})
}

#Preview("保存中 · 禁用") {
    TaskTemplateEditorSaveBar(isDisabled: true, onSave: {})
}

#Preview("保存 · 最大字号") {
    TaskTemplateEditorSaveBar(isDisabled: false, onSave: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}
