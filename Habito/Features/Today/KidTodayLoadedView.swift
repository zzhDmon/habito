import SwiftUI

/// 今日任务成功加载后的推荐卡与其余任务；布局和进度由今日页统一承载。
struct KidTodayLoadedView: View {
    let content: TodayScreenContent
    let makeTimingPresentation: @MainActor (KidTaskNavigationItem) -> KidTaskTimingPresentation
    let onSelectTask: (KidTaskNavigationItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            if let recommendedTask = content.recommendedTask {
                Label("kidToday.nowLabel", systemImage: "sparkles")
                    .font(.title2)
                    .bold()
                KidTaskCard(task: recommendedTask, makeTimingPresentation: { makeTimingPresentation(recommendedTask) })
                {
                    onSelectTask(recommendedTask)
                }
            }

            if !content.remainingTaskGroups.isEmpty {
                Text("kidToday.nextLabel")
                    .font(.title2)
                    .bold()
                    .padding(.top, HabitoDesign.Spacing.small)

                // iPadOS 27 的懒加载容器在重载后会画出末组，却不暴露其标题/按钮。
                // 当前单日清单优先完整无障碍树；不限制任务数量，长清单性能另做探针。
                VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                    ForEach(content.remainingTaskGroups) { group in
                        KidTodayTaskGroupView(
                            group: group, makeTimingPresentation: makeTimingPresentation, onSelectTask: onSelectTask)
                    }
                }
            }
        }
    }
}

#Preview("今日任务 · 推荐与其余") {
    KidTodayLoadedView(
        content: .preview, makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }
    ).padding()
}

#Preview("今日任务 · 大字窄栏") {
    KidTodayLoadedView(
        content: .preview, makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }
    )
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
        makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }
    )
    .padding()
    .frame(width: 834, height: 600)
}
