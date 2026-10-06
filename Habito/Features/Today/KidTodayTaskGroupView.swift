import SwiftUI

/// 只展示用例已经分好的剩余任务，不排序、不折叠、不改变推荐或任务事实。
struct KidTodayTaskGroupView: View {
    let group: TodayTaskGroup
    let onSelectTask: (KidTaskNavigationItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(HabitoAccessibilityID.todayTaskGroupTitle(group.id))
            LazyVStack(spacing: HabitoDesign.Spacing.small) {
                ForEach(group.tasks) { task in
                    KidTaskListRow(task: task) { onSelectTask(task) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 时段标题复用正式编辑器术语；跨日单独说明，不把上一日的任务说成今天的安排。
    private var title: LocalizedStringKey {
        switch group.id {
        case .carryOver: "kidToday.carryOverGroupTitle"
        case .timePeriod(.morning): "taskEditor.timePeriod.morning"
        case .timePeriod(.afterSchool): "taskEditor.timePeriod.afterSchool"
        case .timePeriod(.evening): "taskEditor.timePeriod.evening"
        case .timePeriod(.allDay): "taskEditor.timePeriod.allDay"
        }
    }
}

#Preview("全天组 · 正常") {
    KidTodayTaskGroupView(
        group: TodayTaskGroup(id: .timePeriod(.allDay), tasks: [.previewWriting]), onSelectTask: { _ in }
    )
    .padding()
}

#Preview("全天组 · 最大字号") {
    KidTodayTaskGroupView(
        group: TodayTaskGroup(id: .timePeriod(.allDay), tasks: [.previewWriting]), onSelectTask: { _ in }
    )
    .padding()
    .frame(width: 320)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("跨日组 · 继续原任务") {
    if let task = TodayScreenContent.previewCarryOver.recommendedTask {
        KidTodayTaskGroupView(group: TodayTaskGroup(id: .carryOver, tasks: [task]), onSelectTask: { _ in }).padding()
    }
}
