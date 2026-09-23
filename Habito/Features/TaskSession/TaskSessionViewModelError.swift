import Foundation

/// 任务执行页面在定位持久化实例时可能遇到的错误。
enum TaskSessionViewModelError: Error, Equatable, Sendable {
    case occurrenceNotFound(occurrenceID: UUID)
}
