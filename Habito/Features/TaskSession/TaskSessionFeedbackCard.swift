import SwiftUI

/// 一次性结果卡只渲染保存收据，不读取余额、计算奖励或把预期金额当成到账。
///
/// 事件 ID 控制局部视觉生命周期；关闭、撤销、刷新仍由原页面用例负责。
struct TaskSessionFeedbackCard: View {
    // 只属于当前收据视图的主 actor 视觉状态；不存入数据库，也不影响完成或撤销时间。
    @State private var hasRevealed = false
    let presentation: TaskSessionFeedbackPresentation
    let reduceMotion: Bool
    let onDismiss: () -> Void

    var body: some View {
        let motion = TaskSessionFeedbackMotion(reduceMotion: reduceMotion, hasRevealed: hasRevealed)
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            switch presentation.tone {
            case .submitted:
                Label("taskSession.submittedTitle", systemImage: "paperplane.fill")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("taskSession.submittedDescription")
                    .font(.body)
                Label {
                    Text("taskSession.waitingBadge")
                } icon: {
                    Image(systemName: "clock").accessibilityHidden(true)
                }
                .font(.headline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(HabitoAccessibilityID.submissionFeedbackBadge)
            case .completed, .autonomous:
                TaskCompletionCelebrationView(
                    isAutonomous: presentation.tone == .autonomous,
                    hasReward: presentation.hasReward
                )
                if presentation.hasReward {
                    Text("taskSession.rewardReceiptTitle")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                if let xp = presentation.xp {
                    TaskCompletionRewardCard(
                        text: String.localizedStringWithFormat(String(localized: "taskSession.rewardXPFormat"), xp),
                        symbol: "star.fill", tint: HabitoDesign.Feedback.xp,
                        identifier: HabitoAccessibilityID.rewardXP
                    )
                }
                if let coins = presentation.coins {
                    TaskCompletionRewardCard(
                        text: String.localizedStringWithFormat(
                            String(localized: "taskSession.rewardCoinFormat"), coins),
                        symbol: "circle.fill", tint: HabitoDesign.Feedback.coins,
                        identifier: HabitoAccessibilityID.rewardCoins
                    )
                }
            }
            Button(action: onDismiss) {
                Text("taskSession.feedbackDismiss")
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(HabitoAccessibilityID.dismissCompletionFeedback)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card)
                .strokeBorder(HabitoDesign.Feedback.autonomous.opacity(HabitoDesign.Feedback.badgeTintOpacity))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        // 信息从第一帧就可读、按钮从不禁用；静音无需音效，Reduce Motion 直接显示完整静态结果。
        .scaleEffect(motion.scale)
        .opacity(motion.opacity)
        .animation(motion.animatesReveal ? HabitoDesign.Feedback.reveal : nil, value: hasRevealed)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .task(id: presentation.id, reveal)
        // 结果卡拥有独立分组；否则 17 的容器标识会继承到子按钮/金额，抹掉它们的精确标识。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.completionFeedback)
    }

    private func reveal() async {
        hasRevealed = true
    }
}
