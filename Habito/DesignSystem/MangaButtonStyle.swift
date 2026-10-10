import SwiftUI

/// 主动作不设固定高度；辅助字号允许换行增高，按压仅改变亮度而不移动热区。
struct MangaButtonStyle: ButtonStyle {
    var isPrimary = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(isPrimary ? HabitoDesign.Manga.actionInk : HabitoDesign.Manga.ink)
            .padding(HabitoDesign.Spacing.medium)
            .frame(minWidth: HabitoDesign.Layout.minimumTapSize, minHeight: HabitoDesign.Layout.minimumTapSize)
            .modifier(
                MangaPanel(
                    fill: isPrimary ? HabitoDesign.Manga.action : HabitoDesign.Manga.panel, emphasized: isPrimary)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.55)
    }
}
