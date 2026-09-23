import SwiftUI

/// 今日页中的儿童友好任务大卡。
struct KidTaskCard: View {
    let task: KidTaskNavigationItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                HStack(alignment: .top, spacing: HabitoDesign.Spacing.medium) {
                    Image(systemName: task.iconName)
                        .font(.largeTitle)
                        .foregroundStyle(HabitoDesign.Palette.task)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                        Text(task.title)
                            .font(.title2)
                            .bold()
                            .foregroundStyle(.primary)

                        Label("kidTask.statusPending", systemImage: HabitoDesign.Symbol.pending)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: HabitoDesign.Spacing.small)
                }

                LabeledContent("kidTask.scheduleLabel", value: task.scheduledTimeText)
                LabeledContent("kidTask.durationLabel", value: task.targetDurationText)

                Label("kidToday.openTask", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(HabitoDesign.Palette.accent)
            }
            .padding(HabitoDesign.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card)
                    .stroke(HabitoDesign.Palette.task, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
        }
        .buttonStyle(.plain)
        .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
        .accessibilityHint("kidToday.openTaskHint")
    }
}

#Preview("任务大卡") {
    KidTaskCard(task: .previewReading, action: {})
        .padding()
}
