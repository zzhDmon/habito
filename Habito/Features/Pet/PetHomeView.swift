import SwiftUI

/// 小狗主页复用现有名字事实；不展示尚未定义的等级、心情或喂食数值。
struct PetHomeView: View {
    let model: PetProfileViewModel
    let onOpenParent: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                DogCharacter()
                switch model.state {
                case .loading:
                    ProgressView { Text("pet.loading", tableName: "UIR1") }
                case .notConfigured:
                    MangaSpeechBubble {
                        Text("pet.welcome", tableName: "UIR1").font(.title2.bold())
                    }
                    Text("pet.setupDescription", tableName: "UIR1")
                        .accessibilityIdentifier(HabitoAccessibilityID.petNotConfigured)
                    parentButton
                case let .loaded(names):
                    Text(names.petName)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(HabitoAccessibilityID.petName)
                    MangaSpeechBubble {
                        Text("pet.companion", tableName: "UIR1").font(.title2.bold())
                    }
                    parentButton
                case .failed:
                    Text("pet.error", tableName: "UIR1")
                        .accessibilityIdentifier(HabitoAccessibilityID.petError)
                    Button(action: model.load) { Text("pet.retry", tableName: "UIR1") }
                        .buttonStyle(MangaButtonStyle())
                        .accessibilityIdentifier(HabitoAccessibilityID.petRetry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HabitoDesign.Spacing.large)
            .modifier(MangaPanel(fill: HabitoDesign.Manga.warmPaper, emphasized: true))
            .padding(HabitoDesign.Spacing.large)
            .frame(maxWidth: HabitoDesign.Layout.maximumContentWidth)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(HabitoDesign.Manga.ink)
        .background(HabitoDesign.Manga.paper)
        .navigationTitle(Text("pet.title", tableName: "UIR1"))
        .accessibilityIdentifier(HabitoAccessibilityID.petScreen)
        .task { model.load() }
    }

    private var parentButton: some View {
        Button(action: onOpenParent) { Text("pet.parentAction", tableName: "UIR1") }
            .buttonStyle(MangaButtonStyle())
            .accessibilityIdentifier(HabitoAccessibilityID.petOpenParent)
    }
}

#Preview("小狗 · 未设置横屏") {
    NavigationStack { PetHomeView(model: PetProfileViewModel(loadNames: { nil }), onOpenParent: {}) }
        .frame(width: 1194, height: 834)
}

#Preview("小狗 · 真实名字大字") {
    NavigationStack {
        PetHomeView(
            model: PetProfileViewModel(loadNames: { try FamilyProfileNames(childNickname: "小禾", petName: "奶油小毛球") }),
            onOpenParent: {})
    }.environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("小狗 · 失败深色") {
    NavigationStack {
        PetHomeView(
            model: PetProfileViewModel(loadNames: { throw FamilyProfileServiceError.pendingContextChanges }),
            onOpenParent: {})
    }.preferredColorScheme(.dark)
}
