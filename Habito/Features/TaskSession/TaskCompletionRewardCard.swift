import SwiftUI

/// 奖励卡只接收已经保存的金额与完整到账文案，不做增量计数或模拟货币飞入。
struct TaskCompletionRewardCard: View {
    let text: String
    let symbol: String
    let tint: Color
    let identifier: String

    var body: some View {
        Label {
            Text(text)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.medium)
        .background(
            tint.opacity(HabitoDesign.Feedback.cardTintOpacity),
            in: .rect(cornerRadius: HabitoDesign.CornerRadius.badge)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("真实金币到账 · 大字") {
    TaskCompletionRewardCard(
        text: String.localizedStringWithFormat(String(localized: "taskSession.rewardCoinFormat"), 10),
        symbol: "circle.fill", tint: HabitoDesign.Feedback.coins, identifier: HabitoAccessibilityID.rewardCoins
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
