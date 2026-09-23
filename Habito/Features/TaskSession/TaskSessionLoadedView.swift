import SwiftUI

/// 任务执行页的已加载内容；只渲染页面值并转发操作意图。
struct TaskSessionLoadedView: View {
    let content: TaskSessionScreenContent
    let onStartOrResume: () -> Void
    let onPause: () -> Void

    var body: some View {
        AdaptiveTwoColumnLayout {
            TaskSessionIdentityPanel(task: content.task)
        } trailing: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                TaskSessionTimerPanel(
                    content: content,
                    now: context.date,
                    onStartOrResume: onStartOrResume,
                    onPause: onPause
                )
            }
        }
    }
}

private struct TaskSessionIdentityPanel: View {
    let task: KidTaskNavigationItem

    var body: some View {
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
    }
}

private struct TaskSessionTimerPanel: View {
    let content: TaskSessionScreenContent
    let now: Date
    let onStartOrResume: () -> Void
    let onPause: () -> Void

    private var elapsedSeconds: TimeInterval {
        content.displayedActiveDuration(at: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Text("taskSession.elapsedTitle")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(TaskSessionDurationText.clock(elapsedSeconds))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("taskSession.elapsedTitle")
                .accessibilityValue(TaskSessionDurationText.spoken(elapsedSeconds))

            ProgressView(value: content.progress(at: now))
                .tint(HabitoDesign.Palette.accent)
                .accessibilityLabel("taskSession.goalProgress")
                .accessibilityValue(
                    Text(
                        content.progress(at: now),
                        format: .percent.precision(.fractionLength(0))
                    )
                )

            LabeledContent("kidTask.goalTitle", value: content.task.targetDurationText)
            LabeledContent("kidTask.scheduleLabel", value: content.task.scheduledTimeText)

            TaskSessionPrimaryButton(
                action: content.primaryAction,
                onStartOrResume: onStartOrResume,
                onPause: onPause
            )
            .padding(.top, HabitoDesign.Spacing.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card)
        )
    }
}

private struct TaskSessionPrimaryButton: View {
    let action: TaskSessionScreenContent.PrimaryAction
    let onStartOrResume: () -> Void
    let onPause: () -> Void

    var body: some View {
        switch action {
        case .start:
            actionButton("taskSession.start", systemImage: "play.fill", action: onStartOrResume)
        case .pause:
            actionButton("taskSession.pause", systemImage: "pause.fill", action: onPause)
        case .resume:
            actionButton("taskSession.resume", systemImage: "play.fill", action: onStartOrResume)
        case .none:
            EmptyView()
        }
    }

    private func actionButton(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titleKey, systemImage: systemImage)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

private enum TaskSessionDurationText {
    static func clock(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func spoken(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String.localizedStringWithFormat(
            String(localized: "taskSession.elapsedSpokenFormat"),
            seconds / 60,
            seconds % 60
        )
    }
}

#Preview("任务执行 · 运行中 · iPad 横屏") {
    NavigationStack {
        TaskSessionLoadedView(
            content: TaskSessionScreenContent(
                task: KidTaskNavigationItem(
                    id: UUID(),
                    title: String(localized: "kidTask.previewTitle"),
                    iconName: "book.fill",
                    scheduledTimeText: String(localized: "kidTask.previewTime"),
                    targetDurationText: String(localized: "kidTask.previewDuration"),
                    status: .inProgress,
                    statusText: String(localized: "kidTask.statusInProgress"),
                    statusIconName: "play.circle.fill"
                ),
                targetDurationSeconds: 900,
                activeSessionState: .running,
                activeDurationAtSnapshot: 125,
                snapshotAt: .now
            ),
            onStartOrResume: {},
            onPause: {}
        )
        .navigationTitle("kidTask.navigationTitle")
    }
    .frame(width: 1_194, height: 834)
}
