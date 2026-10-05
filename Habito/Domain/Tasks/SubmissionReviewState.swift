/// 仅描述一次提交的审核结果，不替换旧任务 pending/inProgress/completed/skipped 原始值。
nonisolated enum SubmissionReviewState: String, CaseIterable, Sendable {
    case waiting
    case approved
    case returned
}
