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
                ChildIdentityBadge()
            }
            Section {
                TextField("familyProfile.childNickname", text: $childNickname)
                    .focused(focus, equals: HabitoAccessibilityID.familyProfileChild)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // 普通字号也使用足够大的原生带边框输入区域，不把Form行留白误作TextField触控尺寸。
                    .font(.largeTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .contentShape(.rect)
                    .accessibilityIdentifier(HabitoAccessibilityID.familyProfileChild)
                TextField("familyProfile.petName", text: $petName)
                    .focused(focus, equals: HabitoAccessibilityID.familyProfilePet)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.largeTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .contentShape(.rect)
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
