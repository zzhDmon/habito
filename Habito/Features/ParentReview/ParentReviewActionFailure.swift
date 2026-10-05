/// 审核入口需要向家长明确反馈的失败类别；页面接入时再映射本地化文案。
nonisolated enum ParentReviewActionFailure: Equatable, Sendable {
    case changedSubmission
    case unavailable
    case saveFailed
}
