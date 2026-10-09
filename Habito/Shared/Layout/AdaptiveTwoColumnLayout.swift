import SwiftUI

/// 根据当前容器而非具体设备型号，在双栏和单栏之间切换。
///
/// 横向空间充足时两块内容并排；竖屏或辅助功能字号下改为纵向排列，避免文字被压缩。
struct AdaptiveTwoColumnLayout<Leading: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let scrollsColumnsIndependently: Bool
    private let leading: Leading
    private let trailing: Trailing

    init(
        scrollsColumnsIndependently: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.scrollsColumnsIndependently = scrollsColumnsIndependently
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if scrollsColumnsIndependently && usesTwoColumns(in: geometry.size) {
                    // 两个滚动容器共享可用高度，不共享偏移；右侧长清单不会带走左侧进度。
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            leading.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .contentMargins(HabitoDesign.Spacing.large)
                        .accessibilityIdentifier("kid.today.leading-scroll")
                        ScrollView {
                            trailing.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .contentMargins(HabitoDesign.Spacing.large)
                        .accessibilityIdentifier("kid.today.tasks-scroll")
                    }
                } else {
                    ScrollView {
                        if usesTwoColumns(in: geometry.size) {
                            HStack(alignment: .top, spacing: HabitoDesign.Spacing.xLarge) {
                                leading.frame(maxWidth: .infinity, alignment: .topLeading)
                                trailing.frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                                leading
                                trailing
                            }
                        }
                    }
                    .contentMargins(HabitoDesign.Spacing.large)
                }
            }
            .frame(maxWidth: HabitoDesign.Layout.maximumContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func usesTwoColumns(in size: CGSize) -> Bool {
        size.width > size.height
            && size.width >= 2 * (HabitoDesign.Layout.columnMinimumWidth + 2 * HabitoDesign.Spacing.large)
            && !dynamicTypeSize.isAccessibilitySize
    }
}
