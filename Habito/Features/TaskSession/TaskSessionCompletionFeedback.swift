import Foundation

/// 只由本页面新保存成功的事务产生一次反馈；重新加载历史不能凭空再次庆祝或发奖。
///
/// 提交收据没有 XP/Coin 字段，显示层必须与真实完成结算分支区分，不能展示“预计奖励到账”。
nonisolated enum TaskSessionCompletionFeedback: Equatable, Identifiable, Sendable {
    case submitted(TaskSubmissionResult)
    case completed(TaskCompletionResult)

    var id: UUID {
        switch self {
        case let .submitted(result): result.submissionID
        case let .completed(result): result.completionID
        }
    }
}
