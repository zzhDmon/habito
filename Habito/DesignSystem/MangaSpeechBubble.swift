import SwiftUI

/// 对话文字保持原生可选择的布局高度；尾巴只是装饰，不产生额外读屏内容。
struct MangaSpeechBubble<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(HabitoDesign.Manga.ink)
            .padding(HabitoDesign.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(MangaPanel())
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(HabitoDesign.Manga.panel)
                    .frame(width: HabitoDesign.Spacing.medium, height: HabitoDesign.Spacing.medium)
                    .rotationEffect(.degrees(45))
                    .overlay(alignment: .bottom) {
                        // 尾部独立留在气泡外；不把正文裁切成任意形状。
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.bold))
                            .foregroundStyle(HabitoDesign.Manga.ink)
                            .offset(y: HabitoDesign.Spacing.xSmall)
                    }
                    .offset(x: HabitoDesign.Spacing.large, y: HabitoDesign.Spacing.small)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, HabitoDesign.Spacing.small)
    }
}

#Preview("气泡 · 大字") {
    MangaSpeechBubble { Text("kidToday.greeting").font(.title2.bold()) }
        .padding().environment(\.dynamicTypeSize, .accessibility5)
}
