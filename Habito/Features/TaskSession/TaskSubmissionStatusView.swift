import SwiftUI

/// 提交与完成分开呈现；不把冻结的 expected 金额显示为已经到账。
struct TaskSubmissionStatusView: View {
    let submission: TaskSubmissionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            if submission.state == .waiting {
                Label("kidTask.statusAwaitingReview", systemImage: "hourglass.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(HabitoDesign.Palette.accent)
                Text("taskSession.waitingDescription")
                    .font(.body)
            } else if submission.state == .returned {
                Label("kidTask.statusReturned", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.title2.bold())
                Text("taskSession.returnedDescription")
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.medium)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.badge))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(HabitoAccessibilityID.submissionStatus)
    }
}

#Preview("等待 · 横屏") {
    TaskSubmissionStatusView(
        submission: TaskSubmissionSnapshot(
            id: UUID(), submittedAt: .now, state: .waiting,
            reviewedAt: nil, timing: .beforeReminder, activeDurationSeconds: 120, expectedXP: 11, expectedCoins: 10)
    )
    .padding()
    .frame(width: 600)
}

#Preview("退回 · 大字") {
    TaskSubmissionStatusView(
        submission: TaskSubmissionSnapshot(
            id: UUID(), submittedAt: .now, state: .returned,
            reviewedAt: .now, timing: .beforeReminder, activeDurationSeconds: 120, expectedXP: 11, expectedCoins: 10)
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}
