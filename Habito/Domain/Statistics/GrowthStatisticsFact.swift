import Foundation

/// 一个实例的当前有效事实；查询层负责验证审计，计算层不持有 SwiftData 模型。
///
/// - Important: date 是实例所属日期；不以实际提交、审核或到账日替换。
///   未完成的 timing/source 必须为空，旧完成的 timing 为 unknown 而不是推断值。
nonisolated struct GrowthStatisticsFact: Equatable, Sendable, Identifiable {
    let id: UUID
    let templateID: UUID
    let date: LocalDate
    let title: String
    let status: TaskOccurrenceStatus
    let isAwaitingReview: Bool
    let completionTiming: CompletionTiming?
    let completionSource: CompletionSource?
}
