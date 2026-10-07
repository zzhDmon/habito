import SwiftUI

/// 只描述窗口和查询状态，比例/排序/持久化全部在计算器及页面模型完成。
struct GrowthStatisticsBody: View {
    let state: GrowthStatisticsViewState
    let period: GrowthStatisticsPeriod
    let onSelect: (GrowthStatisticsPeriod) -> Void
    let onRetry: () -> Void

    var body: some View {
        List {
            Section {
                GrowthStatisticsPeriodButtons(period: period, onSelect: onSelect)
                Button(action: onRetry) {
                    Label("statistics.refresh", systemImage: "arrow.clockwise")
                        .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(HabitoAccessibilityID.statisticsRefresh)
            }
            switch state {
            case .idle, .loading:
                ProgressView("statistics.loading")
            case .failed:
                ContentUnavailableView {
                    Label("statistics.errorTitle", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("statistics.errorDescription")
                } actions: {
                    Button(action: onRetry) {
                        Text("statistics.retry")
                            .frame(
                                minWidth: HabitoDesign.Layout.minimumTapSize,
                                minHeight: HabitoDesign.Layout.minimumTapSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(HabitoAccessibilityID.statisticsRetry)
                }
                // 容器只分组，不将错误ID传播到重试按钮，保留独立VoiceOver操作。
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(HabitoAccessibilityID.statisticsError)
            case let .loaded(snapshot):
                Section {
                    Text("statistics.dateWindow \(snapshot.start.dateKey) \(snapshot.end.dateKey)")
                        .accessibilityIdentifier(HabitoAccessibilityID.statisticsWindow)
                    GrowthStatisticsCountsView(
                        counts: snapshot.counts, identifier: HabitoAccessibilityID.statisticsTotal)
                } header: {
                    Text("statistics.summary")
                }
                Section {
                    Text("statistics.completionHint")
                    Text("statistics.autonomyHint")
                    Text("statistics.historyHint")
                } header: {
                    Text("statistics.rules")
                }
                if snapshot.counts.eligible == 0 {
                    ContentUnavailableView(
                        "statistics.emptyTitle", systemImage: "chart.bar",
                        description: Text("statistics.emptyDescription"))
                }
                Section {
                    ForEach(snapshot.days) { day in
                        GrowthStatisticsTrendRow(
                            day: day,
                            identifier: HabitoAccessibilityID.statisticsDay(day.date.dateKey))
                    }
                } header: {
                    Text("statistics.daily")
                }
                Section {
                    ForEach(snapshot.tasks) { task in GrowthStatisticsTaskSection(task: task) }
                } header: {
                    Text("statistics.tasks")
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.statisticsScreen)
    }
}

#Preview("统计 · 正常横屏", traits: .landscapeLeft) {
    GrowthStatisticsBody(state: GrowthStatisticsPreview.state, period: .week, onSelect: { _ in }, onRetry: {})
}
#Preview("统计 · 完成MAX") {
    GrowthStatisticsBody(state: GrowthStatisticsPreview.completedState, period: .week, onSelect: { _ in }, onRetry: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}
#Preview("统计 · 空") {
    GrowthStatisticsBody(state: GrowthStatisticsPreview.emptyState, period: .week, onSelect: { _ in }, onRetry: {})
}
#Preview("统计 · 错误") {
    GrowthStatisticsBody(state: .failed, period: .month, onSelect: { _ in }, onRetry: {})
}
