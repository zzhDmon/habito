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
    let completionFeedback: TaskSessionCompletionFeedback?
    let onDismissCompletionFeedback: () -> Void

    init(
        content: TaskSessionScreenContent, snoozeState: TaskSnoozeState, onStartOrResume: @escaping () -> Void,
        onPause: @escaping () -> Void, onSnooze: @escaping () async -> Void, onComplete: @escaping () -> Void,
        onUndoCompletion: @escaping () -> Void, currentDate: @escaping () -> Date,
        completionFeedback: TaskSessionCompletionFeedback? = nil, onDismissCompletionFeedback: @escaping () -> Void = {}
    ) {
        self.content = content
        self.snoozeState = snoozeState
        self.onStartOrResume = onStartOrResume
        self.onPause = onPause
        self.onSnooze = onSnooze
        self.onComplete = onComplete
        self.onUndoCompletion = onUndoCompletion
        self.currentDate = currentDate
        self.completionFeedback = completionFeedback
        self.onDismissCompletionFeedback = onDismissCompletionFeedback
    }

    var body: some View {
        AdaptiveTwoColumnLayout {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                TaskSessionIdentityPanel(task: content.task)
                if let completionFeedback {
                    TaskSessionResultFeedbackView(feedback: completionFeedback, onDismiss: onDismissCompletionFeedback)
                        // 新保存事件才拥有新的视觉状态；原事件的刷新不重置入场效果。
                        .id(completionFeedback.id)
                }
            }
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

#Preview("任务执行 · 等待确认 · 横屏") {
    TaskSessionLoadedView(
        content: .previewReview(.waiting), snoozeState: .idle,
        onStartOrResume: {}, onPause: {}, onSnooze: {}, onComplete: {}, onUndoCompletion: {}, currentDate: { .now }
    )
    .frame(width: 1_194, height: 834)
}

#Preview("任务执行 · 退回 · 辅助大字") {
    TaskSessionLoadedView(
        content: .previewReview(.returned), snoozeState: .idle,
        onStartOrResume: {}, onPause: {}, onSnooze: {}, onComplete: {}, onUndoCompletion: {}, currentDate: { .now }
    )
    .environment(\.dynamicTypeSize, .accessibility3)
    .frame(width: 1_194, height: 834)
}

private extension TaskSessionScreenContent {
    /// 只构造纯值，不写持久化容器；预期奖励用来检查待审核页面不会显示到账。
    static func previewReview(_ state: SubmissionReviewState) -> Self {
        Self(
            task: .previewReading, targetDurationSeconds: 900,
            activeSessionState: nil, activeDurationAtSnapshot: 120,
            snapshotAt: .now, completion: nil,
            submission: TaskSubmissionSnapshot(
                id: UUID(), submittedAt: .now, state: state,
                reviewedAt: state == .returned ? .now : nil, timing: .beforeReminder,
                activeDurationSeconds: 120, expectedXP: 11, expectedCoins: 10
            ),
            verificationType: .parentApproval
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
                    id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
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
