import SwiftUI

/// 展示当前完成事实；短时撤销入口由执行页底栏单独承载，不被大字内容挤出首屏。
struct TaskCompletionSnapshotView: View {
    let completion: TodayTaskCompletion

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            Label("taskSession.completedTitle", systemImage: HabitoDesign.Symbol.completed)
                .font(.headline)
                .foregroundStyle(HabitoDesign.Palette.success)

            LabeledContent("taskSession.completedAt") {
                Text(completion.completedAt, style: .time)
            }

            LabeledContent(
                "taskSession.actualDuration",
                value: TaskSessionDurationText.spoken(completion.activeDurationSeconds)
            )

        }
        .padding(.top, HabitoDesign.Spacing.small)
    }
}

#Preview("完成事实 · 大字") {
    TaskCompletionSnapshotView(
        completion: TodayTaskCompletion(
            id: UUID(), completedAt: .now, activeDurationSeconds: 780, source: .childManual)
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("完成事实 · 撤销已过期") {
    TaskCompletionSnapshotView(
        completion: TodayTaskCompletion(
            id: UUID(), completedAt: .now, activeDurationSeconds: 780, source: .childManual)
    )
    .padding()
}
