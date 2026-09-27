import Foundation

/// 通知重建无法安全完成时的领域或持久化错误。
nonisolated enum NotificationRebuildError: Error, Equatable, Sendable {
    case invalidHorizonDays(Int)
    case calendarCalculationFailed
    case duplicateAppSettings
    case missingRule(UUID)
    case disabledRuleForActiveTemplate(UUID)
    case invalidOccurrenceDate(UUID, String)
    case invalidOccurrenceStatus(UUID, String)
    case invalidDayOverride(UUID, String)
}
