import SwiftUI

/// 用户触发失败的明确语义：旧请求冲突、数据/状态不可用与底层保存失败分开。
struct ParentReviewActionErrorMessageView: View {
    let failure: ParentReviewActionFailure?

    var body: some View {
        switch failure {
        case .changedSubmission: Text("parentReview.changedSubmission")
        case .unavailable: Text("parentReview.unavailable")
        case .saveFailed, nil: Text("parentReview.saveFailed")
        }
    }
}

#Preview("审核失败") {
    ParentReviewActionErrorMessageView(failure: .saveFailed).padding()
}
