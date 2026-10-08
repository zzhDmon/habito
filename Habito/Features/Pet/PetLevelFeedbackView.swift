import SwiftUI

/// 只展示已经领取的真实升级；按钮与正文首帧可用，减少动态时不依赖任何动画。
struct PetLevelFeedbackView: View {
    let reduceMotion: Bool
    let event: PetGrowthObservation?
    let failed: Bool
    let onContinue: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            if failed {
                VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                    Text("pet.levelUpError", tableName: "UIR1")
                        .accessibilityIdentifier(HabitoAccessibilityID.petLevelUpError)
                    Button(action: onRetry) { Text("pet.levelUpRetry", tableName: "UIR1") }
                        .buttonStyle(MangaButtonStyle()).accessibilityIdentifier(HabitoAccessibilityID.petLevelUpRetry)
                }.padding(HabitoDesign.Spacing.large).modifier(MangaPanel())
            } else if let event, event.didLevelUp {
                VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                    Text("pet.levelUp", tableName: "UIR1").font(.title.bold())
                    DogCharacter(celebrating: true)
                    MangaSpeechBubble {
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "pet.levelUpFormat", table: "UIR1"), event.currentLevel)
                        )
                        .font(.title2.bold()).accessibilityIdentifier(HabitoAccessibilityID.petLevelUp)
                    }
                    Text("pet.levelUpDescription", tableName: "UIR1")
                    Button(action: onContinue) { Text("pet.continue", tableName: "UIR1") }
                        .buttonStyle(MangaButtonStyle()).accessibilityIdentifier(
                            HabitoAccessibilityID.petLevelUpContinue)
                }.padding(HabitoDesign.Spacing.large).modifier(
                    MangaPanel(fill: HabitoDesign.Manga.successPaper, emphasized: true)
                )
                .transition(.opacity)
            }
        }.animation(reduceMotion ? nil : HabitoDesign.Feedback.reveal, value: event)
    }
}

#Preview("升级 · 减少动态大字") {
    PetLevelFeedbackView(
        reduceMotion: true, event: PetGrowthObservation(previousLevel: 1, currentLevel: 3), failed: false,
        onContinue: {}, onRetry: {}
    )
    .environment(\.dynamicTypeSize, .accessibility5).padding()
}

#Preview("升级 · 失败深色") {
    PetLevelFeedbackView(reduceMotion: true, event: nil, failed: true, onContinue: {}, onRetry: {})
        .preferredColorScheme(.dark).padding()
}
