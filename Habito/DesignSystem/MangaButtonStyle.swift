import SwiftUI

/// 主动作不设固定高度；辅助字号允许换行增高，按压仅改变亮度而不移动热区。
struct MangaButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(HabitoDesign.Manga.actionInk)
            .padding(HabitoDesign.Spacing.medium)
            .frame(minWidth: HabitoDesign.Layout.minimumTapSize, minHeight: HabitoDesign.Layout.minimumTapSize)
            .modifier(MangaPanel(fill: HabitoDesign.Manga.action, emphasized: true))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.55)
    }
}
