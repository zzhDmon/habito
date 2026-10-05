import Foundation

/// 页面读取的提交事实；expected 奖励只是冻结的待验收预期，不是到账资产或可消费余额。
nonisolated struct TaskSubmissionSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let submittedAt: Date
    let state: SubmissionReviewState
    let reviewedAt: Date?
    let timing: CompletionTiming
    let activeDurationSeconds: TimeInterval
    let expectedXP: Int
    let expectedCoins: Int
}
