import SwiftUI

/// 只按页面快照展示允许的操作，等待实例由外层状态面板代替，不留可绕过的按钮。
struct TaskSessionControlsView: View {
    let primaryAction: TaskSessionScreenContent.PrimaryAction
    let canComplete: Bool
    let verificationType: TaskVerificationType
    let snoozeState: TaskSnoozeState
    let onStartOrResume: () -> Void
    let onPause: () -> Void
    let onSnooze: () async -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: HabitoDesign.Spacing.small) {
            switch primaryAction {
            case .start:
                TaskSessionActionButton(
                    titleKey: "taskSession.start",
                    systemImage: "play.fill",
                    identifier: HabitoAccessibilityID.startButton,
                    action: onStartOrResume
                )
                .buttonStyle(MangaButtonStyle())
            case .pause:
                TaskSessionActionButton(
                    titleKey: "taskSession.pause",
                    systemImage: "pause.fill",
                    identifier: HabitoAccessibilityID.pauseButton,
                    action: onPause
                )
                .buttonStyle(MangaButtonStyle())
            case .resume:
                TaskSessionActionButton(
                    titleKey: "taskSession.resume",
                    systemImage: "play.fill",
                    identifier: HabitoAccessibilityID.resumeButton,
                    action: onStartOrResume
                )
                .buttonStyle(MangaButtonStyle())
            case .none:
                EmptyView()
            }

            if canComplete {
                Button(action: scheduleSnooze) {
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
                    Label(
                        LocalizedStringKey(
                            verificationType == .parentApproval ? "taskSession.submitForReview" : "taskSession.complete"
                        ),
                        systemImage: verificationType == .parentApproval ? "paperplane.fill" : "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .tint(HabitoDesign.Manga.successInk)
                .controlSize(.large)
                .accessibilityIdentifier(
                    verificationType == .parentApproval
                        ? HabitoAccessibilityID.submitButton : HabitoAccessibilityID.completeButton)
            }
        }
        .padding(.top, HabitoDesign.Spacing.small)
    }

    private func scheduleSnooze() {
        Task { await onSnooze() }
    }
}

#Preview("审核任务 · 可提交 · 横屏") {
    TaskSessionControlsView(
        primaryAction: .start, canComplete: true, verificationType: .parentApproval, snoozeState: .idle,
        onStartOrResume: {}, onPause: {}, onSnooze: {}, onComplete: {}
    )
    .padding()
    .frame(width: 600)
}

#Preview("普通任务 · 暂停 · 大字") {
    TaskSessionControlsView(
        primaryAction: .resume, canComplete: true, verificationType: .selfConfirm, snoozeState: .notificationsDisabled,
        onStartOrResume: {}, onPause: {}, onSnooze: {}, onComplete: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}
