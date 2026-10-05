import Foundation

/// 区分重建保留元数据与孩子明确创建新稍后请求，避免默认 nil 覆盖已保存轮次。
///
/// 不以 createdAt 推断轮次：稳定槽位替换仍保留首次创建时刻，提交与退回也可能同时发生。
nonisolated enum NotificationSubmissionEpochUpdate: Equatable, Sendable {
    case preserve
    case replace(UUID?)
}
