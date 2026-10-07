import SwiftUI

/// 概况复用同一组保存事实；分母和来源不隐藏在颜色、折线或未经解释的数字中。
struct GrowthStatisticsCountsView: View {
    let counts: GrowthStatisticsCounts
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            GrowthStatisticsRateView(
                title: "statistics.completionRate", rate: counts.completionRate,
                numerator: counts.completed, denominator: counts.eligible, identifier: identifier + ".completion")
            GrowthStatisticsRateView(
                title: "statistics.autonomyRate", rate: counts.autonomyRate,
                numerator: counts.autonomous, denominator: counts.knownTiming, identifier: identifier + ".autonomy")
            Text("statistics.waitingCount \(counts.awaitingReview)")
                .accessibilityIdentifier(identifier + ".waiting")
            Text("statistics.sources \(counts.childConfirmed) \(counts.parentApproved) \(counts.parentCorrected)")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(identifier + ".sources")
            if counts.unknownTiming > 0 {
                Text("statistics.unknownCount \(counts.unknownTiming)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(identifier + ".unknown")
            }
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

#Preview("计数 · 无样本横屏", traits: .landscapeLeft) {
    GrowthStatisticsCountsView(counts: .init(facts: []), identifier: "preview.empty")
        .padding()
}

#Preview("计数 · 完成MAX") {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.completedState {
        GrowthStatisticsCountsView(counts: snapshot.counts, identifier: "preview.completed")
            .padding().environment(\.dynamicTypeSize, .accessibility5)
    }
}
