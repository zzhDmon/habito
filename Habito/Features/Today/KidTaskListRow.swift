import SwiftUI

/// 推荐卡之外的今日任务行，状态始终同时显示图标和文字。
struct KidTaskListRow: View {
    let task: KidTaskNavigationItem
    let makeTimingPresentation: @MainActor () -> KidTaskTimingPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // 三时间和状态各占一行，避免最大字号下横向争抢宽度、把等待状态挤出可操作区域。
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                HStack(alignment: .top, spacing: HabitoDesign.Spacing.medium) {
                    Image(systemName: task.iconName)
                        .font(.title2)
                        .foregroundStyle(HabitoDesign.Palette.task)
                        .frame(
                            minWidth: HabitoDesign.Layout.minimumTapSize,
                            minHeight: HabitoDesign.Layout.minimumTapSize
                        )
                        .accessibilityHidden(true)
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                KidTaskTimingView(makePresentation: makeTimingPresentation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: task.targetDurationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .accessibilityIdentifier(HabitoAccessibilityID.task(task.id))
        .accessibilityHint("kidToday.openTaskHint")
    }
}

#Preview("任务行 · 最大字号") {
    KidTaskListRow(
        task: .previewWriting, makeTimingPresentation: { .preview(for: .previewWriting) }, action: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("任务行 · 三时间横屏") {
    KidTaskListRow(
        task: .previewThreeTimes, makeTimingPresentation: { .preview(for: .previewThreeTimes) }, action: {}
    )
    .padding()
    .frame(width: 834, height: 600)
}
