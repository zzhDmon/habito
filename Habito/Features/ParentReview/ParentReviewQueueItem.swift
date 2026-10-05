import Foundation

/// 家长审核页面的不可变请求与原提交快照，不持有 SwiftData 对象。
///
/// id 是提交 ID 而非实例 ID；同一任务重提后成为另一请求，旧按钮不能审核新提交。
/// expected 金额只是原提交通过后可结算的预期，不是已经到账的余额。
nonisolated struct ParentReviewQueueItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let occurrenceID: UUID
    let taskDate: LocalDate
    let title: String
    let iconName: String
    let submittedAt: Date
    let reminderAt: Date
    let activeDurationSeconds: TimeInterval
    let timing: CompletionTiming
    let expectedXP: Int
    let expectedBaseCoins: Int
    let expectedAutonomyCoins: Int
    let expectedCoins: Int
}
