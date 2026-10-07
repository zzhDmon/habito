import SwiftUI

/// 同时展示比例和真实样本，nil与0%有不同文案，VoiceOver不会仅听到颜色或图形。
struct GrowthStatisticsRateView: View {
    let title: LocalizedStringKey
    let rate: Double?
    let numerator: Int
    let denominator: Int
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
            Text(title).font(.headline)
            Group {
                if let rate {
                    Text(rate, format: .percent.precision(.fractionLength(0)))
                } else {
                    Text("statistics.noSamples")
                }
            }
            .font(.title3)
            .accessibilityIdentifier(identifier + ".value")
            Text("statistics.sample \(numerator) \(denominator)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier + ".sample")
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

#Preview("比例 · 无样本与真实0 · MAX") {
    VStack(spacing: HabitoDesign.Spacing.large) {
        GrowthStatisticsRateView(
            title: "statistics.completionRate", rate: nil, numerator: 0, denominator: 0, identifier: "empty")
        GrowthStatisticsRateView(
            title: "statistics.completionRate", rate: 0, numerator: 0, denominator: 3, identifier: "zero")
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
