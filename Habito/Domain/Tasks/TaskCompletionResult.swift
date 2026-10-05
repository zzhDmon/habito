import Foundation

/// 保存成功后的完成收据；不跨 actor 传 SwiftData 对象，也不把重试当新一轮庆祝。
nonisolated struct TaskCompletionResult: Equatable, Sendable {
    let completionID: UUID
    let completedAt: Date
    let timing: CompletionTiming
    let xp: Int
    let coins: Int
    let didComplete: Bool
}
