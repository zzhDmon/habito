import Foundation

/// 保存成功后的一次性家长审核反馈；附实例 ID 供刷新时验证它是否仍对应当前事实。
///
/// 该值不能作为幂等键，也不替代账本。退回/通过重试不生成新反馈，撤销或重提后清理旧反馈。
nonisolated struct ParentReviewFeedback: Equatable, Identifiable, Sendable {
    let occurrenceID: UUID
    let result: TaskSubmissionReviewResult

    var id: UUID { result.submissionID }
}
