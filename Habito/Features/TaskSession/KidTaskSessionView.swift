import SwiftUI

/// 任务执行页的基础视觉结构；计时状态和操作由 M2-004 接入。
struct KidTaskSessionView: View {
    let task: KidTaskNavigationItem

    var body: some View {
        AdaptiveTwoColumnLayout {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                Image(systemName: task.iconName)
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundStyle(HabitoDesign.Palette.task)
                    .accessibilityHidden(true)

                Text(task.title)
                    .font(.largeTitle)
                    .bold()

                Label(task.statusText, systemImage: task.statusIconName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HabitoDesign.Spacing.large)
        } trailing: {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                Text("kidTask.goalTitle")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(task.targetDurationText)
                    .font(.largeTitle)
                    .bold()

                LabeledContent("kidTask.scheduleLabel", value: task.scheduledTimeText)

                Label("kidTask.timerComingSoon", systemImage: "hammer.fill")
                    .font(.headline)
                    .foregroundStyle(HabitoDesign.Palette.accent)
                    .padding(.top, HabitoDesign.Spacing.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HabitoDesign.Spacing.large)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
        }
        .navigationTitle("kidTask.navigationTitle")
        .navigationBarTitleDisplayMode(.inline)
        .background(.background)
    }
}

#Preview("任务执行 · iPad 横屏") {
    NavigationStack {
        KidTaskSessionView(task: .previewReading)
    }
    .frame(width: 1_194, height: 834)
}
