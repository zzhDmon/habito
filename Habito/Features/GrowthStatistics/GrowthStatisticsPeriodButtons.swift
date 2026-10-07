import SwiftUI

/// 三个短窗口按钮在MAX仍保留原生文字与44pt，选中同时使用勾选和VoiceOver特征。
struct GrowthStatisticsPeriodButtons: View {
    let period: GrowthStatisticsPeriod
    let onSelect: (GrowthStatisticsPeriod) -> Void

    var body: some View {
        HStack(spacing: HabitoDesign.Spacing.small) {
            ForEach(GrowthStatisticsPeriod.allCases, id: \.self) { option in
                Button(action: { onSelect(option) }) {
                    VStack(spacing: HabitoDesign.Spacing.xSmall) {
                        Text("statistics.period \(option.rawValue)")
                        Image(systemName: period == option ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .accessibilityAddTraits(period == option ? .isSelected : [])
                .accessibilityIdentifier(HabitoAccessibilityID.statisticsPeriod(option.rawValue))
            }
        }
    }
}

#Preview("统计窗口 · 横屏", traits: .landscapeLeft) {
    GrowthStatisticsPeriodButtons(period: .week, onSelect: { _ in }).padding()
}

#Preview("统计窗口 · 窄宽MAX") {
    GrowthStatisticsPeriodButtons(period: .month, onSelect: { _ in })
        .frame(width: 320).environment(\.dynamicTypeSize, .accessibility5)
}
