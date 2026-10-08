import SwiftUI

/// 小狗主页展示同一份已验证成长快照；喂食写入由注入服务负责，名字编辑仍走PIN。
struct PetHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: PetProfileViewModel
    let onOpenParent: () -> Void
    var levelUp: PetGrowthObservation?
    var growthCheckFailed = false
    var onDismissLevelUp: () -> Void = {}
    var onRetryGrowth: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                PetLevelFeedbackView(
                    reduceMotion: reduceMotion, event: levelUp, failed: growthCheckFailed,
                    onContinue: onDismissLevelUp, onRetry: onRetryGrowth)
                DogCharacter(celebrating: model.feedingReceipt?.didInsert == true)
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
                case let .loaded(snapshot):
                    Text(snapshot.names.petName)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(HabitoAccessibilityID.petName)
                    MangaSpeechBubble {
                        Text("pet.companion", tableName: "UIR1").font(.title2.bold())
                    }
                    PetGrowthSummaryView(snapshot: snapshot)
                    PetFeedingControls(reduceMotion: reduceMotion, model: model, canFeed: snapshot.canFeed)
                    parentButton
                case .failed:
                    if model.feedingReceipt != nil { Text("pet.fedRefreshFailed", tableName: "UIR1") }
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
    NavigationStack { PetHomeView(model: PetPreviewData.model(kind: 0), onOpenParent: {}) }
        .frame(width: 1194, height: 834)
}

#Preview("小狗 · 成长大字") {
    NavigationStack { PetHomeView(model: PetPreviewData.model(kind: 1), onOpenParent: {}) }
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("小狗 · 失败深色") {
    NavigationStack { PetHomeView(model: PetPreviewData.model(kind: 2), onOpenParent: {}) }
        .preferredColorScheme(.dark)
}
