import Foundation
import SwiftData

/// 在主 actor 核对完成快照、原奖励与冲正，供完成重试和撤销共享一致边界。
@MainActor
struct TaskCompletionAuditValidator {
    let context: ModelContext

    /// 只读验证；旧版本 0 不回填快照，有明确原交易才要求相应冲正。
    ///
    /// - Returns: 已验证的账本快照，仍局限于当前主 actor。
    /// - Throws: 完成事实或交易关联不一致，不自动补账或改写历史。
    func validate(_ record: CompletionRecord) throws -> RewardLedgerSnapshot {
        guard record.completionSource != nil, record.completionTiming != nil,
            record.completedAt.timeIntervalSinceReferenceDate.isFinite,
            record.activeDurationSeconds.isFinite, record.activeDurationSeconds >= 0,
            record.rewardSettlementVersion == 0 || record.rewardSettlementVersion == 1
        else { throw TaskCompletionServiceError.invalidStoredCompletion(record.id) }
        let ledger = try RewardLedgerSnapshot(context: context)
        let xp = ledger.xp[RewardLedgerKey.xpReward(record.id)]
        let coin = ledger.coin[RewardLedgerKey.coinReward(record.id)]
        let xpReversal = ledger.xp[RewardLedgerKey.xpReversal(record.id)]
        let coinReversal = ledger.coin[RewardLedgerKey.coinReversal(record.id)]
        if record.rewardSettlementVersion == 1 {
            guard let reminderAt = record.reminderAtSnapshot else {
                throw TaskCompletionServiceError.invalidStoredCompletion(record.id)
            }
            let snapshot = try CompletionRewardSnapshot(
                submittedAt: record.completedAt, reminderAt: reminderAt,
                xp: record.xpRewardSnapshot, baseCoins: record.coinRewardSnapshot,
                autonomyBonusCoins: record.activeBonusCoinSnapshot)
            guard record.completionTiming == snapshot.timing, record.settledCoinSnapshot == snapshot.settledCoins,
                xp?.amount == snapshot.xp, coin?.amount == snapshot.settledCoins,
                xp?.createdAt == record.completedAt, coin?.createdAt == record.completedAt
            else { throw TaskCompletionServiceError.invalidStoredCompletion(record.id) }
        }
        if let revokedAt = record.revokedAt {
            guard revokedAt.timeIntervalSinceReferenceDate.isFinite, revokedAt >= record.completedAt else {
                throw TaskCompletionServiceError.invalidStoredCompletion(record.id)
            }
            if xp != nil {
                guard xpReversal?.createdAt == revokedAt, coinReversal?.createdAt == revokedAt else {
                    throw TaskCompletionServiceError.invalidStoredCompletion(record.id)
                }
            }
        } else {
            guard xpReversal == nil, coinReversal == nil else {
                throw TaskCompletionServiceError.invalidStoredCompletion(record.id)
            }
        }
        return ledger
    }
}
