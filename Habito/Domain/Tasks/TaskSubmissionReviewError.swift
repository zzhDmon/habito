import Foundation

/// 审核请求绑定原提交 ID；冲突和损坏不能降级成“审核最新提交”。
nonisolated enum TaskSubmissionReviewError: Error, Equatable, Sendable {
    case submissionNotFound(UUID)
    case conflictingOutcome(UUID)
    case unavailableState(UUID)
    case timeBeforeSubmission(UUID)
}
