import Foundation

/// 账本明确拒绝的原因；调用方必须反馈失败，不能先庆祝到账。
nonisolated enum RewardLedgerError: Error, Equatable, Sendable {
    case invalidAmount
    case invalidTimestamp
    case timeBeforeReward
    case pendingContextChanges
    case businessKeyConflict(String)
    case corruptLedger(String)
    case rewardNotFound(UUID)
    case insufficientCoins(required: Int, available: Int)
    case integerOverflow
}
