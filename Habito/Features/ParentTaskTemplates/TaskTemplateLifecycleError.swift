import Foundation

/// 模板生命周期操作无法安全执行时的明确原因。
enum TaskTemplateLifecycleError: Error, Equatable {
    case templateNotFound(UUID)
    case missingRule(UUID)
    case invalidOccurrenceDate(UUID, String)
    case invalidOccurrenceStatus(UUID, String)
}
