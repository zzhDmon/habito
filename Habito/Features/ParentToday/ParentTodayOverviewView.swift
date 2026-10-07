import SwiftUI

/// 今日概况独立错误重试，不用旧比例掩盖读取失败，也不替代任务管理列表。
struct ParentTodayOverviewView: View {
    let state: ParentTodayOverviewState
    let onRetry: () -> Void
    let onShowStatistics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Text("statistics.todayTitle").font(.title2)
            switch state {
            case .idle, .loading: ProgressView("statistics.loading")
            case let .loaded(day):
                GrowthStatisticsCountsView(counts: day.counts, identifier: HabitoAccessibilityID.parentTodayOverview)
            case .failed:
                Label("statistics.errorTitle", systemImage: "exclamationmark.triangle")
                Button(action: onRetry) {
                    Text("statistics.retry")
                        .frame(
                            minWidth: HabitoDesign.Layout.minimumTapSize, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .accessibilityIdentifier(HabitoAccessibilityID.parentTodayOverviewRetry)
            }
            Button(action: onShowStatistics) {
                Label("statistics.open", systemImage: "chart.bar")
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            }
            .accessibilityIdentifier(HabitoAccessibilityID.parentTodayStatisticsOpen)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

#Preview("今日概况 · 正常横屏", traits: .landscapeLeft) {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.state, let day = snapshot.days.last {
        ParentTodayOverviewView(state: .loaded(day), onRetry: {}, onShowStatistics: {}).padding()
    }
}

#Preview("今日概况 · 完成MAX") {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.completedState, let day = snapshot.days.last {
        ScrollView {
            ParentTodayOverviewView(state: .loaded(day), onRetry: {}, onShowStatistics: {}).padding()
        }.environment(\.dynamicTypeSize, .accessibility5)
    }
}

#Preview("今日概况 · 空") {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.emptyState, let day = snapshot.days.last {
        ParentTodayOverviewView(state: .loaded(day), onRetry: {}, onShowStatistics: {}).padding()
    }
}

#Preview("今日概况 · 错误") {
    ParentTodayOverviewView(state: .failed, onRetry: {}, onShowStatistics: {}).padding()
}
