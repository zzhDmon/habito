import SwiftUI

/// 一次性结果卡只渲染保存收据，不读取余额、计算奖励或把预期金额当成到账。
///
/// 零奖励仍肯定现实行动；普通/自主分层只用真实时机，不擅定动画、等级或宠物数值。
struct TaskSessionResultFeedbackView: View {
    let feedback: TaskSessionCompletionFeedback
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            switch feedback {
            case .submitted:
                Label("taskSession.submittedTitle", systemImage: "paperplane.fill")
                    .font(.title2.bold())
                Text("taskSession.submittedDescription")
                    .font(.body)
            case let .completed(result):
                Label("taskSession.completedEncouragement", systemImage: "sparkles")
                    .font(.title2.bold())
                    .foregroundStyle(HabitoDesign.Palette.success)
                Text("taskSession.completedEncouragementDescription")
                    .font(.body)
                if result.timing == .beforeReminder {
                    Label("taskSession.autonomyEncouragement", systemImage: "star.circle.fill")
                        .font(.headline)
                }
                if result.xp > 0 {
                    Label {
                        Text(
                            String.localizedStringWithFormat(String(localized: "taskSession.rewardXPFormat"), result.xp)
                        )
                    } icon: {
                        Image(systemName: "star.fill")
                            .accessibilityHidden(true)
                    }
                    .font(.title3.bold())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(HabitoAccessibilityID.rewardXP)
                }
                if result.coins > 0 {
                    Label {
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "taskSession.rewardCoinFormat"), result.coins))
                    } icon: {
                        Image(systemName: "circle.fill")
                            .accessibilityHidden(true)
                    }
                    .font(.title3.bold())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(HabitoAccessibilityID.rewardCoins)
                }
            }
            Button("taskSession.feedbackDismiss", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.dismissCompletionFeedback)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
        // 结果卡拥有独立分组；否则 17 的容器标识会继承到子按钮/金额，抹掉它们的精确标识。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.completionFeedback)
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
