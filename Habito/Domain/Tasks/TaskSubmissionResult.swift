import Foundation

/// 保存成功的提交收据，不是完成/奖励收据；等待阶段不能把快照金额当作实际到账。
nonisolated struct TaskSubmissionResult: Equatable, Sendable {
    let submissionID: UUID
    let submittedAt: Date
    let timing: CompletionTiming
    let activeDurationSeconds: TimeInterval
    let didSubmit: Bool
}
