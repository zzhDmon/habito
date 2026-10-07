import Foundation

/// 查询拒绝未经保存或关联不一致的事实，避免错误被呈现为“孩子没有完成”。
nonisolated enum GrowthStatisticsQueryError: Error, Equatable {
    case pendingContextChanges
    case invalidTimestamp
    case invalidOccurrenceIdentity(UUID)
    case invalidCompletionRelation(UUID)
    case completionAfterQueryTime(UUID)
}
