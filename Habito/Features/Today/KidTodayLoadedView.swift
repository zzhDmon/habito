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

#Preview("今日任务 · 推荐与其余") {
    KidTodayLoadedView(content: .preview, onSelectTask: { _ in }).padding()
}

#Preview("今日任务 · 大字窄栏") {
    KidTodayLoadedView(content: .preview, onSelectTask: { _ in })
        .padding()
        .frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility5)
}
