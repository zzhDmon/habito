import SwiftUI

/// 两名字的局部输入；只有明确保存才生效，未配置不预填示例姓名。
struct FamilyProfileEditorForm: View {
    @Binding var childNickname: String
    @Binding var petName: String
    let focus: FocusState<String?>.Binding
    let hasStoredNames: Bool

    var body: some View {
        Form {
            Section {
                TextField("familyProfile.childNickname", text: $childNickname)
                    .focused(focus, equals: HabitoAccessibilityID.familyProfileChild)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .accessibilityIdentifier(HabitoAccessibilityID.familyProfileChild)
                TextField("familyProfile.petName", text: $petName)
                    .focused(focus, equals: HabitoAccessibilityID.familyProfilePet)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .accessibilityIdentifier(HabitoAccessibilityID.familyProfilePet)
            } header: {
                Text(hasStoredNames ? "familyProfile.editHeader" : "familyProfile.setupHeader")
            } footer: {
                Text("familyProfile.saveDescription")
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.familyProfileForm)
    }
}

#Preview("空表单／横屏", traits: .landscapeLeft) {
    NavigationStack {
        FamilyProfileEditorView(model: FamilyProfileEditorViewModel(loadNames: { nil }, saveNames: { _ in true }))
    }
}
