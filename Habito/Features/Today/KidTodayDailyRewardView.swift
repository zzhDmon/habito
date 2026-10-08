import SwiftUI

/// 仅展示已保存的当天所得；金额与余额分开，重试意图交给页面状态处理。
struct KidTodayDailyRewardView: View {
    let state: TodayDailyRewardState
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Text("daily.title", tableName: "UIR1")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            switch state {
            case .loading:
                ProgressView { Text("daily.loading", tableName: "UIR1") }
            case let .loaded(summary):
                KidRewardAmountView(
                    text: String.localizedStringWithFormat(
                        String(localized: "daily.xpFormat", table: "UIR1"), summary.earnedXP),
                    symbol: "star.fill", tint: HabitoDesign.Manga.ink,
                    identifier: HabitoAccessibilityID.todayDailyXP)
                KidRewardAmountView(
                    text: String.localizedStringWithFormat(
                        String(localized: "daily.coinsFormat", table: "UIR1"), summary.earnedCoins),
                    symbol: "circle.fill", tint: HabitoDesign.Manga.ink,
                    identifier: HabitoAccessibilityID.todayDailyCoins)
                Text("daily.explanation", tableName: "UIR1")
                    .font(.callout)
                    .foregroundStyle(HabitoDesign.Manga.secondaryInk)
            case .failed:
                Text("daily.error", tableName: "UIR1")
                    .accessibilityIdentifier(HabitoAccessibilityID.todayDailyError)
                Button(action: onRetry) { Text("daily.retry", tableName: "UIR1") }
                    .buttonStyle(MangaButtonStyle())
                    .accessibilityIdentifier(HabitoAccessibilityID.todayDailyRetry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(HabitoDesign.Manga.ink)
        .padding(HabitoDesign.Spacing.large)
        .modifier(MangaPanel(fill: HabitoDesign.Manga.warmPaper))
        .accessibilityElement(children: .contain)
    }
}

#Preview("今日所得 · 横屏") {
    KidTodayDailyRewardView(state: .loaded(DailyRewardSummary(earnedXP: 11, earnedCoins: 7)), onRetry: {})
        .frame(width: 450).padding()
}

#Preview("今日所得 · 零值") {
    KidTodayDailyRewardView(state: .loaded(DailyRewardSummary(earnedXP: 0, earnedCoins: 0)), onRetry: {}).padding()
}

#Preview("今日所得 · 错误深色大字") {
    KidTodayDailyRewardView(state: .failed, onRetry: {})
        .environment(\.dynamicTypeSize, .accessibility5).preferredColorScheme(.dark).padding()
}
