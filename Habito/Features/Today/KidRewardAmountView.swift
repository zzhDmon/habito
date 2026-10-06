import SwiftUI

/// 资产名称与真实整数作为一个读屏语义，不逐枚播报装饰符号或靠颜色区分资产。
struct KidRewardAmountView: View {
    let text: String
    let symbol: String
    let tint: Color
    let identifier: String

    var body: some View {
        Label {
            Text(text)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("真实资产 · 大字整数边界") {
    KidRewardAmountView(
        text: String.localizedStringWithFormat(String(localized: "kidRewards.coinsFormat"), Int.max),
        symbol: "circle.fill", tint: HabitoDesign.Feedback.coins, identifier: HabitoAccessibilityID.todayCoins
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
