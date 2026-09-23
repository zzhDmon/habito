import SwiftUI

/// 根据当前容器而非具体设备型号，在双栏和单栏之间切换。
///
/// 横向空间充足时两块内容并排；竖屏或辅助功能字号下改为纵向排列，避免文字被压缩。
struct AdaptiveTwoColumnLayout<Leading: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let leading: Leading
    private let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if usesTwoColumns(in: geometry.size) {
                    HStack(alignment: .top, spacing: HabitoDesign.Spacing.xLarge) {
                        leading
                            .frame(
                                minWidth: HabitoDesign.Layout.columnMinimumWidth,
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                        trailing
                            .frame(
                                minWidth: HabitoDesign.Layout.columnMinimumWidth,
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                    }
                } else {
                    VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                        leading
                        trailing
                    }
                }
            }
            .contentMargins(HabitoDesign.Spacing.large)
            .frame(maxWidth: HabitoDesign.Layout.maximumContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func usesTwoColumns(in size: CGSize) -> Bool {
        size.width > size.height && !dynamicTypeSize.isAccessibilitySize
    }
}
