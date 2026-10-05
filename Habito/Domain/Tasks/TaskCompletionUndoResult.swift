import Foundation

/// 保存后的审计撤销收据；重复旧请求返回原撤销时刻，不作为一次新扣减。
nonisolated struct TaskCompletionUndoResult: Equatable, Sendable {
    let completionID: UUID
    let revokedAt: Date
    let xpDelta: Int
    let coinDelta: Int
    let didUndo: Bool
}
