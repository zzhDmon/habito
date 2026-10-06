import SwiftUI

/// 从真实系统设置读取动态效果策略，并渲染新保存事件；预览不伪造只读系统环境值。
struct TaskSessionResultFeedbackView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let feedback: TaskSessionCompletionFeedback
    let onDismiss: () -> Void

    var body: some View {
        TaskSessionFeedbackCard(
            presentation: TaskSessionFeedbackPresentation(feedback: feedback),
            reduceMotion: reduceMotion, onDismiss: onDismiss
        )
    }
}

#Preview("真实到账 · 横屏") {
    TaskSessionResultFeedbackView(
        feedback: .completed(
            TaskCompletionResult(
                completionID: UUID(), completedAt: .now,
                timing: .beforeReminder, xp: 11, coins: 10, didComplete: true)), onDismiss: {}
    )
    .padding()
    .frame(width: 500)
}

#Preview("零奖励也肯定 · 大字") {
    TaskSessionResultFeedbackView(
        feedback: .completed(
            TaskCompletionResult(
                completionID: UUID(), completedAt: .now,
                timing: .afterReminder, xp: 0, coins: 0, didComplete: true)), onDismiss: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("提交不是到账") {
    TaskSessionResultFeedbackView(
        feedback: .submitted(
            TaskSubmissionResult(
                submissionID: UUID(), submittedAt: .now,
                timing: .beforeReminder, activeDurationSeconds: 120, didSubmit: true)), onDismiss: {}
    )
    .padding()
}

#Preview("静态自主收据 · 最大字号") {
    TaskSessionFeedbackCard(
        presentation: TaskSessionFeedbackPresentation(
            feedback: .completed(
                TaskCompletionResult(
                    completionID: UUID(), completedAt: .now,
                    timing: .beforeReminder, xp: 11, coins: 10, didComplete: true))),
        reduceMotion: true, onDismiss: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
