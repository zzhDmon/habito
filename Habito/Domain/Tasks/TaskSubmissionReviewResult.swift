import Foundation

/// 保存后的审核事实；didReview 为 false 不应再次庆祝，已撤销奖励也不能展示成新到账。
nonisolated struct TaskSubmissionReviewResult: Equatable, Sendable {
    let submissionID: UUID
    let state: SubmissionReviewState
    let submittedAt: Date
    let reviewedAt: Date
    let completionID: UUID?
    let timing: CompletionTiming
    let xp: Int
    let coins: Int
    let rewardIsRevoked: Bool
    let didReview: Bool
}
