import SwiftUI

/// PIN 解锁后的审核页面；仅订阅用例状态并转发明确提交请求，不编排持久化写入。
struct ParentReviewView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ParentReviewViewModel

    init(model: ParentReviewViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        ParentReviewContentView(
            state: model.state, feedback: model.feedback,
            onApprove: model.approve, onReturn: model.returnForRevision,
            onRetry: model.load, onDismissFeedback: model.dismissFeedback
        )
        .navigationTitle("parentReview.navigationTitle")
        .task(model.prepareForPresentation)
        .onDisappear(perform: model.dismissFeedback)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
        .alert("parentReview.actionErrorTitle", isPresented: $model.isActionErrorPresented) {
        } message: {
            ParentReviewActionErrorMessageView(failure: model.actionFailure)
        }
    }
}

#Preview("受保护审核页 · 内存空库") {
    NavigationStack {
        ParentReviewView(model: ParentReviewPreview.emptyModel())
    }
}
