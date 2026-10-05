import Foundation

/// 防止维护性删除跨上下文或抹掉任务审计。
nonisolated enum TaskGraphDeletionError: Error, Equatable, Sendable {
    case modelNotInContext
    case protectedHistory(UUID)
}
