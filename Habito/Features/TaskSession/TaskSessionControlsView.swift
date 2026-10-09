import SwiftUI

/// 只按页面快照展示允许的操作，等待实例由外层状态面板代替，不留可绕过的按钮。
struct TaskSessionControlsView: View {
    @State private var isCompletionConfirmationPresented = false

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

                Button(action: requestCompletion) {
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
        .alert(
            Text("completion.confirm.title", tableName: "UIR1"),
            isPresented: $isCompletionConfirmationPresented
        ) {
            Button(role: .cancel) {
                isCompletionConfirmationPresented = false
            } label: {
                Text("completion.confirm.cancel", tableName: "UIR1")
            }
            .accessibilityIdentifier(HabitoAccessibilityID.cancelCompletionButton)
            Button(action: onComplete) {
                if verificationType == .parentApproval {
                    Text("completion.confirm.submit", tableName: "UIR1")
                } else {
                    Text("completion.confirm.save", tableName: "UIR1")
                }
            }
            .accessibilityIdentifier(HabitoAccessibilityID.confirmCompletionButton)
        } message: {
            if verificationType == .parentApproval {
                Text("completion.confirm.reviewMessage", tableName: "UIR1")
            } else {
                Text("completion.confirm.message", tableName: "UIR1")
            }
        }
    }

    /// 第一次点击只打开确认；最终确认才调用原用例，因此取消不写库，完成时间也不会提前冻结。
    private func requestCompletion() {
        isCompletionConfirmationPresented = true
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
