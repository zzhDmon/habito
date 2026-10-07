import SwiftUI

/// 文字与图标共同表达结果，不用绿色或红色作为唯一成功/失败线索。
struct FamilyProfileEditorFeedbackView: View {
    let feedback: FamilyProfileEditorFeedback

    var body: some View {
        Label(message, systemImage: feedback == .saved ? "checkmark.circle" : "exclamationmark.circle")
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(HabitoAccessibilityID.familyProfileFeedback)
    }

    private var message: LocalizedStringKey {
        switch feedback {
        case .saved: "familyProfile.saved"
        case .storageFailure: "familyProfile.saveError"
        case .validation(.emptyChildNickname): "familyProfile.emptyChild"
        case .validation(.emptyPetName): "familyProfile.emptyPet"
        case .validation(.lineBreakInChildNickname): "familyProfile.lineBreakChild"
        case .validation(.lineBreakInPetName): "familyProfile.lineBreakPet"
        }
    }
}

#Preview("空字段反馈") {
    FamilyProfileEditorFeedbackView(feedback: .validation(.emptyChildNickname))
}
