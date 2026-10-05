#if DEBUG
    import Foundation
    import SwiftData

    /// 只有显式 UI 测试启动才注入审核保存失败，不影响正式 Debug 家庭库或 Release。
    @MainActor
    enum UITestReviewServiceFactory {
        static let failureArgument = "--habito-ui-review-save-fail"

        static func make(context: ModelContext, arguments: [String]) -> TaskSubmissionReviewService {
            guard arguments.contains(UITestLaunchConfiguration.enableArgument), arguments.contains(failureArgument)
            else { return TaskSubmissionReviewService(context: context) }
            return TaskSubmissionReviewService(
                context: context,
                saveChanges: { _ in throw NSError(domain: "HabitoSyntheticUIReviewSave", code: 1) })
        }
    }
#endif
