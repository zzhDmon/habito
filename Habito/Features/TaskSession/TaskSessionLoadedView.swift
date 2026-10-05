import SwiftUI

/// 任务执行页的已加载内容；只渲染页面值并转发操作意图。
struct TaskSessionLoadedView: View {
    let content: TaskSessionScreenContent
    let snoozeState: TaskSnoozeState
    let onStartOrResume: () -> Void
    let onPause: () -> Void
    let onSnooze: () async -> Void
    let onComplete: () -> Void
    let onUndoCompletion: () -> Void
    let currentDate: () -> Date

    var body: some View {
        AdaptiveTwoColumnLayout {
            TaskSessionIdentityPanel(task: content.task)
        } trailing: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                TaskSessionTimerPanel(
                    content: content,
                    snoozeState: snoozeState,
                    now: currentDate(),
                    onStartOrResume: onStartOrResume,
                    onPause: onPause,
                    onSnooze: onSnooze,
                    onComplete: onComplete,
                    onUndoCompletion: onUndoCompletion
                )
            }
        }
        .accessibilityIdentifier(HabitoAccessibilityID.sessionScreen)
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
    let snoozeState: TaskSnoozeState
    let now: Date
    let onStartOrResume: () -> Void
    let onPause: () -> Void
    let onSnooze: () async -> Void
    let onComplete: () -> Void
    let onUndoCompletion: () -> Void

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
                .accessibilityIdentifier(HabitoAccessibilityID.elapsedTime)

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

            if let completion = content.completion {
                TaskCompletionSnapshotView(
                    completion: completion,
                    undoRemainingSeconds: content.undoRemainingSeconds(at: now),
                    canUndo: content.canUndoCompletion(at: now),
                    onUndo: onUndoCompletion
                )
            } else {
                TaskSessionControlsView(
                    primaryAction: content.primaryAction,
                    canComplete: content.canComplete,
                    snoozeState: snoozeState,
                    onStartOrResume: onStartOrResume,
                    onPause: onPause,
                    onSnooze: onSnooze,
                    onComplete: onComplete
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card)
        )
    }
}

private struct TaskSessionControlsView: View {
    let primaryAction: TaskSessionScreenContent.PrimaryAction
    let canComplete: Bool
    let snoozeState: TaskSnoozeState
    let onStartOrResume: () -> Void
    let onPause: () -> Void
    let onSnooze: () async -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: HabitoDesign.Spacing.small) {
            switch primaryAction {
            case .start:
                primaryButton(
                    "taskSession.start",
                    systemImage: "play.fill",
                    identifier: HabitoAccessibilityID.startButton,
                    action: onStartOrResume
                )
            case .pause:
                primaryButton(
                    "taskSession.pause",
                    systemImage: "pause.fill",
                    identifier: HabitoAccessibilityID.pauseButton,
                    action: onPause
                )
            case .resume:
                primaryButton(
                    "taskSession.resume",
                    systemImage: "play.fill",
                    identifier: HabitoAccessibilityID.resumeButton,
                    action: onStartOrResume
                )
            case .none:
                EmptyView()
            }

            if canComplete {
                Button {
                    Task { await onSnooze() }
                } label: {
                    Label("taskSession.snooze", systemImage: "bell.badge.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(snoozeState == .scheduling)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeButton)

                TaskSnoozeFeedbackView(state: snoozeState)

                Button(action: onComplete) {
                    Label("taskSession.complete", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .tint(HabitoDesign.Palette.success)
                .controlSize(.large)
                .accessibilityIdentifier(HabitoAccessibilityID.completeButton)
            }
        }
        .padding(.top, HabitoDesign.Spacing.small)
    }

    private func primaryButton(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titleKey, systemImage: systemImage)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
    }
}

private struct TaskSnoozeFeedbackView: View {
    let state: TaskSnoozeState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .scheduling:
            Label("taskSession.snoozeScheduling", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .scheduled:
            Label("taskSession.snoozeScheduled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(HabitoDesign.Palette.success)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .crossesMidnight:
            Label("taskSession.snoozeMidnight", systemImage: "moon.stars.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .budgetFull:
            Label("taskSession.snoozeBudgetFull", systemImage: "bell.slash.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .unavailable:
            Label("taskSession.snoozeUnavailable", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .failed:
            Label("taskSession.snoozeFailed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .notificationsDisabled:
            Label("taskSession.snoozeNotificationsDisabled", systemImage: "bell.slash.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        }
    }
}

private struct TaskCompletionSnapshotView: View {
    let completion: TodayTaskCompletion
    let undoRemainingSeconds: Int
    let canUndo: Bool
    let onUndo: () -> Void

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

            if canUndo {
                Button(action: onUndo) {
                    Label {
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "taskSession.undoFormat"),
                                undoRemainingSeconds
                            )
                        )
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                    }
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, HabitoDesign.Spacing.small)
                .accessibilityIdentifier(HabitoAccessibilityID.undoButton)
            }
        }
        .padding(.top, HabitoDesign.Spacing.small)
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
                snapshotAt: .now,
                completion: nil
            ),
            snoozeState: .idle,
            onStartOrResume: {},
            onPause: {},
            onSnooze: {},
            onComplete: {},
            onUndoCompletion: {},
            currentDate: { .now }
        )
        .navigationTitle("kidTask.navigationTitle")
    }
    .frame(width: 1_194, height: 834)
}

#Preview("任务执行 · 完成与撤销 · iPad 横屏") {
    NavigationStack {
        TaskSessionLoadedView(
            content: TaskSessionScreenContent(
                task: .previewCompleted,
                targetDurationSeconds: 900,
                activeSessionState: nil,
                activeDurationAtSnapshot: 780,
                snapshotAt: .now,
                completion: TodayTaskCompletion(
                    completedAt: .now,
                    activeDurationSeconds: 780,
                    source: .childManual
                )
            ),
            snoozeState: .idle,
            onStartOrResume: {},
            onPause: {},
            onSnooze: {},
            onComplete: {},
            onUndoCompletion: {},
            currentDate: { .now }
        )
        .navigationTitle("kidTask.navigationTitle")
    }
    .frame(width: 1_194, height: 834)
}
