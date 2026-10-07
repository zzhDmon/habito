import SwiftUI

/// 模板稳定ID承载改名后的同一任务；按需展开日明细，避免一次创建全部任务×30行。
struct GrowthStatisticsTaskSection: View {
    let task: GrowthStatisticsTask
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            // 原生DisclosureGroup在17/27导出文字大小的AX区域；显式Button保留44pt操作区。
            Button(action: toggleExpanded) {
                Label(task.title, systemImage: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("statistics.expanded") : Text("statistics.collapsed"))
            .accessibilityIdentifier(HabitoAccessibilityID.statisticsTaskDisclosure(task.id))
            if isExpanded {
                GrowthStatisticsCountsView(
                    counts: task.counts,
                    identifier: HabitoAccessibilityID.statisticsTask(task.id))
                ForEach(task.days) { day in
                    GrowthStatisticsTrendRow(
                        day: day,
                        identifier: HabitoAccessibilityID.statisticsTaskDay(task.id, dateKey: day.date.dateKey))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func toggleExpanded() { isExpanded.toggle() }
}

#Preview("任务趋势 · 可展开横屏", traits: .landscapeLeft) {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.completedState, let task = snapshot.tasks.first {
        List { GrowthStatisticsTaskSection(task: task) }
    }
}

#Preview("任务趋势 · MAX") {
    if case let .loaded(snapshot) = GrowthStatisticsPreview.state, let task = snapshot.tasks.first {
        List { GrowthStatisticsTaskSection(task: task) }.environment(\.dynamicTypeSize, .accessibility5)
    }
}
