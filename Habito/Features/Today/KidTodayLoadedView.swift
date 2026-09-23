import SwiftUI

/// 今日页成功加载后的推荐卡、其余任务和进度布局。
struct KidTodayLoadedView: View {
    let content: TodayScreenContent
    let onSelectTask: (KidTaskNavigationItem) -> Void

    var body: some View {
        AdaptiveTwoColumnLayout {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                KidTodayGreetingPanel()
                KidTodayProgressView(
                    completedCount: content.completedCount,
                    totalCount: content.totalCount
                )
            }
        } trailing: {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                if let recommendedTask = content.recommendedTask {
                    Label("kidToday.nowLabel", systemImage: "sparkles")
                        .font(.title2)
                        .bold()
                    KidTaskCard(task: recommendedTask) {
                        onSelectTask(recommendedTask)
                    }
                }

                if !content.remainingTasks.isEmpty {
                    Text("kidToday.nextLabel")
                        .font(.title2)
                        .bold()
                        .padding(.top, HabitoDesign.Spacing.small)

                    LazyVStack(spacing: HabitoDesign.Spacing.small) {
                        ForEach(content.remainingTasks) { task in
                            KidTaskListRow(task: task) {
                                onSelectTask(task)
                            }
                        }
                    }
                }
            }
        }
    }
}
