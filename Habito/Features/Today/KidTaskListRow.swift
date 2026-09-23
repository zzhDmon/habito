import SwiftUI

/// 推荐卡之外的今日任务行，状态始终同时显示图标和文字。
struct KidTaskListRow: View {
    let task: KidTaskNavigationItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HabitoDesign.Spacing.medium) {
                Image(systemName: task.iconName)
                    .font(.title2)
                    .foregroundStyle(HabitoDesign.Palette.task)
                    .frame(
                        minWidth: HabitoDesign.Layout.minimumTapSize,
                        minHeight: HabitoDesign.Layout.minimumTapSize
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(verbatim: "\(task.scheduledTimeText) · \(task.targetDurationText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: HabitoDesign.Spacing.small)

                Label(task.statusText, systemImage: task.statusIconName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(HabitoDesign.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
        }
        .buttonStyle(.plain)
        .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
        .accessibilityHint("kidToday.openTaskHint")
    }
}
