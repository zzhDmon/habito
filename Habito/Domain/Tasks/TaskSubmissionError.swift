import Foundation

/// 提交边界错误；等待审核不是普通未开始任务，不能绕过事实直接计时或发奖。
nonisolated enum TaskSubmissionError: Error, Equatable, Sendable {
    case parentApprovalRequired(UUID)
    case awaitingReview(UUID)
    case unavailableState(UUID)
    case corruptHistory(UUID)
    case timeBeforePreviousReview(UUID)
    case sequenceOverflow(UUID)
}
