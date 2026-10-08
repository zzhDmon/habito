import SwiftUI

/// 展示稳定任务身份和可读状态，不通过颜色独自表达等待或完成。
struct TaskSessionIdentityPanel: View {
    let task: KidTaskNavigationItem
    let makeTimingPresentation: @MainActor () -> KidTaskTimingPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
            TaskIcon(storedName: task.iconName)

            Text(task.title)
                .font(.largeTitle)
                .bold()

            Label(task.statusText, systemImage: task.statusIconName)
                .font(.title3)
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)

            KidTaskTimingView(makePresentation: makeTimingPresentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .foregroundStyle(HabitoDesign.Manga.ink)
        .modifier(MangaPanel(fill: HabitoDesign.Manga.warmPaper))
    }
}

#Preview("任务身份 · 大字") {
    TaskSessionIdentityPanel(
        task: .previewReading, makeTimingPresentation: { .preview(for: .previewReading) }
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("任务身份 · 三时间最大字号") {
    TaskSessionIdentityPanel(
        task: .previewThreeTimes, makeTimingPresentation: { .preview(for: .previewThreeTimes) }
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
