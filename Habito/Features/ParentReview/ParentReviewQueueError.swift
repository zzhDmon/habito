import Foundation

/// 孤儿审计或坏日期不能变成“没有待审核任务”；底层存储和领域审计错误继续透传。
nonisolated enum ParentReviewQueueError: Error, Equatable, Sendable {
    case occurrenceNotFound(UUID)
    case invalidTaskDate(UUID, String)
}
