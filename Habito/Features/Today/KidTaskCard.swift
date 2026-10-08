import SwiftUI

/// 今日页中的儿童友好任务大卡。
struct KidTaskCard: View {
    let task: KidTaskNavigationItem
    let makeTimingPresentation: @MainActor () -> KidTaskTimingPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                HStack(alignment: .top, spacing: HabitoDesign.Spacing.medium) {
                    TaskIcon(storedName: task.iconName)

                    VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                        Text(task.title)
                            .font(.title2)
                            .bold()
                            .foregroundStyle(HabitoDesign.Manga.ink)

                        Label(task.statusText, systemImage: task.statusIconName)
                            .font(.headline)
                            .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                    }

                    Spacer(minLength: HabitoDesign.Spacing.small)
                }

                KidTaskTimingView(makePresentation: makeTimingPresentation)
                LabeledContent("kidTask.durationLabel", value: task.targetDurationText)

                Label("kidToday.openTask", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(HabitoDesign.Manga.actionInk)
                    .padding(HabitoDesign.Spacing.small)
                    .modifier(MangaPanel(fill: HabitoDesign.Manga.action))
            }
            .padding(HabitoDesign.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(HabitoDesign.Manga.ink)
            .modifier(MangaPanel(emphasized: true))
            .contentShape(RoundedRectangle(cornerRadius: HabitoDesign.Manga.corner))
        }
        .buttonStyle(.plain)
        .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
        .accessibilityIdentifier(HabitoAccessibilityID.task(task.id))
        .accessibilityHint("kidToday.openTaskHint")
    }
}

#Preview("任务大卡") {
    KidTaskCard(
        task: .previewReading, makeTimingPresentation: { .preview(for: .previewReading) }, action: {}
    )
    .padding()
}

#Preview("任务大卡 · 三时间最大字号") {
    KidTaskCard(
        task: .previewThreeTimes, makeTimingPresentation: { .preview(for: .previewThreeTimes) }, action: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
