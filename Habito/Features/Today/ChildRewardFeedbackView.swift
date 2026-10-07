import SwiftUI

/// 非模态的真实审核反馈；只转发当前完成 ID，不在 View 写库或追加奖励。
struct ChildRewardFeedbackView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: ChildRewardFeedbackState
    let acknowledgementFailed: Bool
    let onContinue: (UUID) -> Void
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .failed:
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                Label("childReceipt.loadError", systemImage: "exclamationmark.circle")
                    .font(.headline)
                    .accessibilityIdentifier(HabitoAccessibilityID.childReceiptError)
                Text("childReceipt.loadErrorHint").font(.body)
                Button(action: onRetry) {
                    Label("childReceipt.retry", systemImage: "arrow.clockwise")
                        .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(HabitoAccessibilityID.childReceiptRetry)
            }
        case let .receipt(receipt):
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                Label("childReceipt.approved", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(HabitoAccessibilityID.childReceiptApproved)
                Text(receipt.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(HabitoAccessibilityID.childReceiptTaskTitle)
                if acknowledgementFailed {
                    Text("childReceipt.acknowledgementError")
                        .font(.body)
                        .accessibilityIdentifier(HabitoAccessibilityID.childReceiptError)
                }
                TaskSessionFeedbackCard(
                    presentation: TaskSessionFeedbackPresentation(receipt: receipt),
                    reduceMotion: reduceMotion, onDismiss: continueReading
                )
                .id(receipt.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(HabitoAccessibilityID.childReceipt)
        }
    }

    private func continueReading() {
        guard case let .receipt(receipt) = state else { return }
        onContinue(receipt.id)
    }
}

#Preview("审核后自主到账 · 横屏") {
    ChildRewardFeedbackView(
        state: .receipt(.preview), acknowledgementFailed: false, onContinue: { _ in }, onRetry: {}
    )
    .padding()
    .frame(width: 550)
}

#Preview("零奖励 · 最大字号") {
    ChildRewardFeedbackView(
        state: .receipt(.previewZero), acknowledgementFailed: false, onContinue: { _ in }, onRetry: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("确认失败可重试") {
    ChildRewardFeedbackView(
        state: .receipt(.preview), acknowledgementFailed: true, onContinue: { _ in }, onRetry: {}
    )
    .padding()
}

#Preview("读取错误不影响任务") {
    ChildRewardFeedbackView(state: .failed, acknowledgementFailed: false, onContinue: { _ in }, onRetry: {})
        .padding()
}

#Preview("没有未读收据") {
    ChildRewardFeedbackView(state: .idle, acknowledgementFailed: false, onContinue: { _ in }, onRetry: {})
}
