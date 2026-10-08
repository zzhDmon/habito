import SwiftUI

/// 只描述真实资产状态；读取失败不展示旧余额或零占位，重试仅转发用户意图。
///
/// 没有计数动画、消费入口、等级进度或结算能力；系统减少动态效果与静音不改变信息。
struct KidTodayRewardOverview: View {
    let state: TodayRewardState
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Text("wallet.title", tableName: "UIR1")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            switch state {
            case .loading:
                ProgressView("kidRewards.loading")
            case let .loaded(balance):
                KidRewardAmountView(
                    text: String.localizedStringWithFormat(
                        String(localized: "kidRewards.xpFormat"), balance.effectiveXP),
                    symbol: "star.fill", tint: HabitoDesign.Manga.ink,
                    identifier: HabitoAccessibilityID.todayXP
                )
                KidRewardAmountView(
                    text: String.localizedStringWithFormat(String(localized: "kidRewards.coinsFormat"), balance.coins),
                    symbol: "circle.fill", tint: HabitoDesign.Manga.ink,
                    identifier: HabitoAccessibilityID.todayCoins
                )
            case .failed:
                Label {
                    Text("kidRewards.errorTitle")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                }
                .font(.headline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(HabitoAccessibilityID.todayRewardsError)
                Text("kidRewards.errorDescription")
                    .font(.body)
                Button(action: onRetry) {
                    Text("kidRewards.retry")
                        .frame(
                            minWidth: HabitoDesign.Layout.minimumTapSize,
                            minHeight: HabitoDesign.Layout.minimumTapSize
                        )
                }
                .buttonStyle(MangaButtonStyle())
                .accessibilityIdentifier(HabitoAccessibilityID.todayRewardsRetry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(HabitoDesign.Manga.ink)
        .padding(HabitoDesign.Spacing.large)
        .modifier(MangaPanel())
        // 父分组不能把精确金额与重试按钮的稳定标识覆盖成同一个容器标识。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.todayRewardsOverview)
    }
}

#Preview("收获 · 真实余额") {
    KidTodayRewardOverview(state: .loaded(RewardBalance(effectiveXP: 11, coins: 7)), onRetry: {}).padding()
}

#Preview("收获 · 零余额") {
    KidTodayRewardOverview(state: .loaded(RewardBalance(effectiveXP: 0, coins: 0)), onRetry: {}).padding()
}

#Preview("收获 · 加载") {
    KidTodayRewardOverview(state: .loading, onRetry: {}).padding()
}

#Preview("收获 · 失败大字") {
    KidTodayRewardOverview(state: .failed, onRetry: {})
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
