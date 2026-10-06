import SwiftUI

/// 只展示用例已经分好的剩余任务，不排序、不折叠、不改变推荐或任务事实。
///
/// 原生 `Section` 由外层统一栈安排标题和任务行，避免懒加载生命周期丢失可见任务的无障碍身份。
struct KidTodayTaskGroupView: View {
    let group: TodayTaskGroup
    let makeTimingPresentation: @MainActor (KidTaskNavigationItem) -> KidTaskTimingPresentation
    let onSelectTask: (KidTaskNavigationItem) -> Void

    var body: some View {
        Section {
            ForEach(group.tasks) { task in
                KidTaskListRow(task: task, makeTimingPresentation: { makeTimingPresentation(task) }) {
                    onSelectTask(task)
                }
            }
        } header: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, HabitoDesign.Spacing.medium)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(HabitoAccessibilityID.todayTaskGroupTitle(group.id))
        }
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
    VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
        KidTodayTaskGroupView(
            group: TodayTaskGroup(id: .timePeriod(.allDay), tasks: [.previewWriting]),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in })
    }
    .padding()
}

#Preview("全天组 · 最大字号") {
    VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
        KidTodayTaskGroupView(
            group: TodayTaskGroup(id: .timePeriod(.allDay), tasks: [.previewWriting]),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in })
    }
    .padding()
    .frame(width: 320)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("跨日组 · 继续原任务") {
    if let task = TodayScreenContent.previewCarryOver.recommendedTask {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            KidTodayTaskGroupView(
                group: TodayTaskGroup(id: .carryOver, tasks: [task]),
                makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in })
        }.padding()
    }
}
