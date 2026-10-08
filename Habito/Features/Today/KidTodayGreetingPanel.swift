import SwiftUI

/// 今日页左侧的问候和模式说明。
struct KidTodayGreetingPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            MangaSpeechBubble {
                VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                    Text("kidToday.greeting")
                        .font(.largeTitle.weight(.heavy))
                    Text("kidToday.subtitle")
                        .font(.title3)
                        .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                }
            }

            // 辅助字号优先呈现任务与金额；纯装饰插画不占据额外滚动距离。
            if !dynamicTypeSize.isAccessibilitySize {
                DogCharacter()
            }

            Label("kidToday.childMode", systemImage: "figure.child")
                .font(.headline)
                .padding(.horizontal, HabitoDesign.Spacing.medium)
                .padding(.vertical, HabitoDesign.Spacing.small)
                .modifier(MangaPanel(fill: HabitoDesign.Manga.action))
                .foregroundStyle(HabitoDesign.Manga.actionInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .modifier(MangaPanel(fill: HabitoDesign.Manga.warmPaper, emphasized: true))
    }
}

#Preview("漫画招呼 · 横屏") {
    KidTodayGreetingPanel().padding().frame(width: 440)
}

#Preview("漫画招呼 · 深色大字") {
    KidTodayGreetingPanel().padding().frame(width: 400)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
