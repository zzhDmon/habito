import SwiftUI

/// 根据纯值渲染计时、等待和操作；回调只转发意图，不直接写数据库或排程。
struct TaskSessionTimerPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: TaskSessionScreenContent
    let snoozeState: TaskSnoozeState
    let now: Date
    let onStartOrResume: () -> Void
    let onPause: () -> Void
    let onSnooze: () async -> Void
    let onComplete: () -> Void

    private var elapsedSeconds: TimeInterval {
        content.displayedActiveDuration(at: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Text("taskSession.elapsedTitle")
                .font(.headline)
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)

            Text(TaskSessionDurationText.clock(elapsedSeconds))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("taskSession.elapsedTitle")
                .accessibilityValue(TaskSessionDurationText.spoken(elapsedSeconds))
                .accessibilityIdentifier(HabitoAccessibilityID.elapsedTime)

            ProgressView(value: content.progress(at: now))
                .tint(HabitoDesign.Manga.successInk)
                .accessibilityLabel("taskSession.goalProgress")
                .accessibilityValue(
                    Text(
                        content.progress(at: now),
                        format: .percent.precision(.fractionLength(0))
                    )
                )

            LabeledContent("kidTask.goalTitle", value: content.task.targetDurationText)

            if let submission = content.submission, submission.state == .waiting || submission.state == .returned {
                TaskSubmissionStatusView(submission: submission)
            }

            if let completion = content.completion {
                TaskCompletionSnapshotView(
                    completion: completion
                )
            } else if !content.isAwaitingReview {
                TaskSessionControlsView(
                    primaryAction: content.primaryAction,
                    canComplete: content.canComplete,
                    verificationType: content.verificationType,
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
        .foregroundStyle(HabitoDesign.Manga.ink)
        .modifier(MangaPanel(emphasized: true))
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }
}
