import SwiftUI

/// 无持久化依赖的审核内容；空队列和读取失败分开，单独覆盖横屏/大字预览。
struct ParentReviewContentView: View {
    let state: ParentReviewViewState
    let feedback: ParentReviewFeedback?
    let onApprove: (ParentReviewQueueItem) -> Void
    let onReturn: (ParentReviewQueueItem) -> Void
    let onRetry: () -> Void
    let onDismissFeedback: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                if let feedback {
                    ParentReviewFeedbackView(feedback: feedback, onDismiss: onDismissFeedback)
                }
                switch state {
                case .loading:
                    ProgressView("parentReview.loading")
                case let .loaded(items) where items.isEmpty:
                    ContentUnavailableView(
                        "parentReview.emptyTitle", systemImage: "checkmark.seal",
                        description: Text("parentReview.emptyDescription"))
                case let .loaded(items):
                    Text("parentReview.queueDescription")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    ForEach(items) { item in
                        ParentReviewQueueRow(
                            item: item, onApprove: { onApprove(item) }, onReturn: { onReturn(item) })
                    }
                case .failed:
                    ContentUnavailableView {
                        Label("parentReview.errorTitle", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text("parentReview.errorDescription")
                    } actions: {
                        Button("parentReview.retry", action: onRetry)
                            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                            .accessibilityIdentifier(HabitoAccessibilityID.parentReviewRetry)
                    }
                }
            }
            .frame(maxWidth: HabitoDesign.Layout.maximumContentWidth, alignment: .leading)
            .padding(HabitoDesign.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(HabitoAccessibilityID.parentReviewScreen)
    }
}

#Preview("待验收 · 横屏") {
    NavigationStack {
        ParentReviewContentView(
            state: .loaded([ParentReviewPreview.item]), feedback: nil,
            onApprove: { _ in }, onReturn: { _ in }, onRetry: {}, onDismissFeedback: {}
        )
        .navigationTitle("parentReview.navigationTitle")
    }
    .frame(width: 1024, height: 768)
}

#Preview("空队列") {
    ParentReviewContentView(
        state: .loaded([]), feedback: nil, onApprove: { _ in }, onReturn: { _ in }, onRetry: {}, onDismissFeedback: {})
}

#Preview("读取失败") {
    ParentReviewContentView(
        state: .failed, feedback: nil, onApprove: { _ in }, onReturn: { _ in }, onRetry: {}, onDismissFeedback: {})
}

#Preview("审核完成 · 大字") {
    ParentReviewContentView(
        state: .loaded([]), feedback: ParentReviewPreview.feedback(approved: true),
        onApprove: { _ in }, onReturn: { _ in }, onRetry: {}, onDismissFeedback: {}
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
