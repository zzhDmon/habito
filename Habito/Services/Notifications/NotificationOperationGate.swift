import Foundation

/// 串行执行完整的通知业务事务，而不只是隔离每一条 Swift 语句。
///
/// 主 actor 在 `await` 时允许其他任务进入，因此预算读取、系统写入和映射保存仍可能交错。
/// 组合根给重建与稍后提醒注入同一个 gate，使下一个事务只在前一个结束后读取业务真相。
@MainActor
final class NotificationOperationGate {
    private var isExecuting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// 等待前一事务完成，执行操作，并在成功、失败或取消后交还执行权。
    ///
    /// - Important: 不可在已持有该 gate 的操作内再次调用，否则会等待自身。
    ///   等待中的取消会在取得执行权时抛出，不会执行过期操作，也不会阻塞后续事务。
    func perform<Result>(
        _ operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        if isExecuting {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isExecuting = true
        }
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func release() {
        if waiters.isEmpty {
            isExecuting = false
        } else {
            // 执行权直接交给队首；此处不能先解锁，否则新到请求会越过等待者。
            waiters.removeFirst().resume()
        }
    }
}
