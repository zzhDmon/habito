import Foundation

/// 写入口返回值不包含 SwiftData 活跃对象；只有保存成功后才可用来展示入账收据。
nonisolated struct RewardLedgerMutation: Equatable, Sendable {
    let sourceID: UUID
    let xpDelta: Int
    let coinDelta: Int
    let createdAt: Date
    let didInsert: Bool
}
