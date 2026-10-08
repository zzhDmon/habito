import SwiftUI

/// 固定保存与反馈区域；大字号下不要求家长在键盘后的长表单中寻找保存按钮。
struct FamilyProfileEditorSaveBar: View {
    let feedback: FamilyProfileEditorFeedback?
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            if let feedback {
                FamilyProfileEditorFeedbackView(feedback: feedback)
            }
            Button(action: onSave) {
                Label("familyProfile.save", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
            }
            .buttonStyle(MangaButtonStyle())
            .disabled(isSaving)
            .accessibilityIdentifier(HabitoAccessibilityID.familyProfileSave)
        }
        .padding(HabitoDesign.Spacing.medium)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.familyProfileSaveBar)
    }
}

#Preview("保存成功／最大字号") {
    FamilyProfileEditorSaveBar(feedback: .saved, isSaving: false, onSave: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("保存失败／最大字号") {
    FamilyProfileEditorSaveBar(feedback: .storageFailure, isSaving: false, onSave: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}
