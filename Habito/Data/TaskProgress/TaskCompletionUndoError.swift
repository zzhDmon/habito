import Foundation

/// 撤销请求必须指向准确完成事件，不能在重试时改成当前最新事件。
nonisolated enum TaskCompletionUndoError: Error, Equatable, Sendable {
    case completionNotFound(UUID)
    case completionNotCurrent(UUID)
    case undoWindowExpired(UUID)
}
