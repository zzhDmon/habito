import SwiftUI

/// 真实保存后的家长结果；退回不发奖，零金额通过仍明确确认孩子的行动。
struct ParentReviewFeedbackView: View {
    let feedback: ParentReviewFeedback
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            if feedback.result.state == .approved {
                Label("parentReview.approvedTitle", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                Text("parentReview.approvedDescription")
                if feedback.result.xp > 0 {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "taskSession.rewardXPFormat"), feedback.result.xp)
                    )
                    .font(.title3.bold())
                    .accessibilityIdentifier(HabitoAccessibilityID.parentReviewXP)
                }
                if feedback.result.coins > 0 {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "taskSession.rewardCoinFormat"), feedback.result.coins)
                    )
                    .font(.title3.bold())
                    .accessibilityIdentifier(HabitoAccessibilityID.parentReviewCoins)
                }
            } else if feedback.result.state == .returned {
                Label("parentReview.returnedTitle", systemImage: "arrow.uturn.backward.circle")
                    .font(.title2.bold())
                Text("parentReview.returnedDescription")
            }
            Button("parentReview.dismissFeedback", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentReviewDismissFeedback)
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentReviewFeedback)
    }
}

#Preview("真实通过") {
    ParentReviewFeedbackView(feedback: ParentReviewPreview.feedback(approved: true), onDismiss: {}).padding()
}

#Preview("退回继续 · 大字") {
    ScrollView {
        ParentReviewFeedbackView(feedback: ParentReviewPreview.feedback(approved: false), onDismiss: {}).padding()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
