import Foundation

/// 模板保存后重建已物化实例时发现的持久化边界错误。
enum TaskOccurrenceMaterializationError: Error, Equatable, Sendable {
    case missingRule(UUID)
    case disabledRuleForActiveTemplate(UUID)
    case invalidDayOverride(id: UUID, rawValue: String)
}
