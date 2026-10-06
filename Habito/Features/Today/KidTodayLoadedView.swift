import SwiftUI

/// 今日任务成功加载后的推荐卡与其余任务；布局和进度由今日页统一承载。
struct KidTodayLoadedView: View {
    let content: TodayScreenContent
    let onSelectTask: (KidTaskNavigationItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            if let recommendedTask = content.recommendedTask {
                Label("kidToday.nowLabel", systemImage: "sparkles")
                    .font(.title2)
                    .bold()
                KidTaskCard(task: recommendedTask) {
                    onSelectTask(recommendedTask)
                }
            }

            if !content.remainingTaskGroups.isEmpty {
                Text("kidToday.nextLabel")
                    .font(.title2)
                    .bold()
                    .padding(.top, HabitoDesign.Spacing.small)

                LazyVStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                    ForEach(content.remainingTaskGroups) { group in
                        KidTodayTaskGroupView(group: group, onSelectTask: onSelectTask)
                    }
                }
            }
        }
    }
}

#Preview("今日任务 · 推荐与其余") {
    KidTodayLoadedView(content: .preview, onSelectTask: { _ in }).padding()
}

#Preview("今日任务 · 大字窄栏") {
    KidTodayLoadedView(content: .preview, onSelectTask: { _ in })
        .padding()
        .frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("今日任务 · 四时段横屏") {
    KidTodayLoadedView(
        content: TodayScreenContent(
            recommendedTask: .previewReading,
            remainingTasks: TaskTimePeriod.allCases.map { period in
                KidTaskNavigationItem(
                    id: UUID(), title: String(localized: "kidTask.previewWritingTitle"), iconName: "pencil.line",
                    scheduledTimeText: "19:30", targetDurationText: String(localized: "kidTask.previewDuration"),
                    status: .pending, statusText: String(localized: "kidTask.statusPending"),
                    statusIconName: HabitoDesign.Symbol.pending, timePeriod: period)
            },
            completedCount: 0, totalCount: 5, isAllCompleted: false),
        onSelectTask: { _ in }
    )
    .padding()
    .frame(width: 834, height: 600)
}
