import Foundation

/// 稳定业务键只由来源事件 ID 与交易角色生成，不使用点击时间或 UI 展示状态。
nonisolated enum RewardLedgerKey {
    static func xpReward(_ sourceID: UUID) -> String { "habito.reward.\(sourceID.uuidString.lowercased()).xp" }
    static func coinReward(_ sourceID: UUID) -> String { "habito.reward.\(sourceID.uuidString.lowercased()).coin" }
    static func xpReversal(_ sourceID: UUID) -> String { xpReward(sourceID) + ".reversal" }
    static func coinReversal(_ sourceID: UUID) -> String { coinReward(sourceID) + ".reversal" }
    static func coinSpend(_ sourceID: UUID) -> String { "habito.spend.\(sourceID.uuidString.lowercased()).coin" }
}
