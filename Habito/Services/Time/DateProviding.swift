import Foundation

/// 为需要“当前绝对时间”的功能提供可替换系统边界。
nonisolated protocol DateProviding: Sendable {
    func now() -> Date
}
