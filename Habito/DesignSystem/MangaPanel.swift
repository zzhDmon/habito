import SwiftUI

/// 统一分格边线与硬阴影；内容仍由调用方提供，不复制业务状态。
struct MangaPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var fill: Color = HabitoDesign.Manga.panel
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: HabitoDesign.Manga.corner))
            .overlay {
                RoundedRectangle(cornerRadius: HabitoDesign.Manga.corner)
                    .strokeBorder(
                        HabitoDesign.Manga.ink,
                        lineWidth: emphasized ? HabitoDesign.Manga.border : HabitoDesign.Manga.secondaryBorder
                    )
                    .accessibilityHidden(true)
            }
            .shadow(
                color: emphasized && colorScheme == .light ? HabitoDesign.Manga.ink : .clear,
                radius: 0, x: HabitoDesign.Manga.shadowOffset, y: HabitoDesign.Manga.shadowOffset)
    }
}

#Preview("漫画格 · 深色大字") {
    Text("kidToday.greeting")
        .font(.title).padding()
        .foregroundStyle(HabitoDesign.Manga.ink)
        .modifier(MangaPanel(emphasized: true))
        .padding()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
