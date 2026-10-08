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
                    TaskIcon(storedName: task.iconName)
                        .frame(
                            minWidth: HabitoDesign.Layout.minimumTapSize,
                            minHeight: HabitoDesign.Layout.minimumTapSize
                        )
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(HabitoDesign.Manga.ink)
                }
                KidTaskTimingView(makePresentation: makeTimingPresentation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: task.targetDurationText)
                    .font(.subheadline)
                    .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                Label(task.statusText, systemImage: task.statusIconName)
                    .font(.subheadline)
                    .foregroundStyle(HabitoDesign.Manga.secondaryInk)
            }
            .padding(HabitoDesign.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(HabitoDesign.Manga.ink)
            .modifier(MangaPanel())
            .contentShape(RoundedRectangle(cornerRadius: HabitoDesign.Manga.corner))
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
