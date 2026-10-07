import SwiftUI

/// 每日趋势是可读的日期/样本列表；不把没有实例的历史空日画成退步。
struct GrowthStatisticsTrendRow: View {
    let day: GrowthStatisticsDay
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            Text(day.date.dateKey).font(.headline)
                .accessibilityIdentifier(identifier + ".date")
            GrowthStatisticsRateView(
                title: "statistics.completionRate", rate: day.counts.completionRate,
                numerator: day.counts.completed, denominator: day.counts.eligible,
                identifier: identifier + ".completion")
            GrowthStatisticsRateView(
                title: "statistics.autonomyRate", rate: day.counts.autonomyRate,
                numerator: day.counts.autonomous, denominator: day.counts.knownTiming,
                identifier: identifier + ".autonomy")
            if day.counts.awaitingReview > 0 {
                Text("statistics.waitingCount \(day.counts.awaitingReview)")
                    .accessibilityIdentifier(identifier + ".waiting")
            }
        }
        .padding(.vertical, HabitoDesign.Spacing.small)
        .accessibilityElement(children: .contain)
    }
}

#Preview("每日趋势 · 正常横屏", traits: .landscapeLeft) {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.state, let day = snapshot.days.last {
        GrowthStatisticsTrendRow(day: day, identifier: "preview.day").padding()
    }
}

#Preview("每日趋势 · 完成MAX") {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.completedState, let day = snapshot.days.last {
        GrowthStatisticsTrendRow(day: day, identifier: "preview.day")
            .padding().environment(\.dynamicTypeSize, .accessibility5)
    }
}
