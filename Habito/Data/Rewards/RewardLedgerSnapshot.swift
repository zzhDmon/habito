import Foundation
import SwiftData

/// 在主 actor 读取并验证账本事实；损坏的键、符号、缺半边奖励不能静默算成余额。
@MainActor
struct RewardLedgerSnapshot {
    let xp: [String: XPTransaction]
    let coin: [String: CoinTransaction]
    let balance: RewardBalance

    init(context: ModelContext) throws {
        let xpRows = try context.fetch(FetchDescriptor<XPTransaction>())
        let coinRows = try context.fetch(FetchDescriptor<CoinTransaction>())
        var xpByKey: [String: XPTransaction] = [:]
        var coinByKey: [String: CoinTransaction] = [:]
        var xpIDs: Set<UUID> = []
        var coinIDs: Set<UUID> = []
        for row in xpRows {
            guard xpByKey[row.businessKey] == nil, xpIDs.insert(row.id).inserted else {
                throw RewardLedgerError.corruptLedger(row.businessKey)
            }
            xpByKey[row.businessKey] = row
        }
        for row in coinRows {
            guard coinByKey[row.businessKey] == nil, coinIDs.insert(row.id).inserted else {
                throw RewardLedgerError.corruptLedger(row.businessKey)
            }
            coinByKey[row.businessKey] = row
        }
        for row in xpRows { try Self.validate(row, xp: xpByKey, coin: coinByKey) }
        for row in coinRows { try Self.validate(row, xp: xpByKey, coin: coinByKey) }
        let effectiveXP = try RewardBalance.checkedTotal(xpRows.map(\.amount))
        let coins = try RewardBalance.checkedTotal(coinRows.map(\.amount))
        guard effectiveXP >= 0, coins >= 0 else { throw RewardLedgerError.corruptLedger("negative-balance") }
        self.xp = xpByKey
        self.coin = coinByKey
        self.balance = RewardBalance(effectiveXP: effectiveXP, coins: coins)
    }

    private static func validate(_ row: XPTransaction, xp: [String: XPTransaction], coin: [String: CoinTransaction])
        throws
    {
        var valid = row.createdAt.timeIntervalSinceReferenceDate.isFinite
        switch row.kind {
        case .reward:
            valid =
                valid && row.businessKey == RewardLedgerKey.xpReward(row.sourceID)
                && row.amount >= 0 && row.reversalOfBusinessKey == nil
            let partner = coin[RewardLedgerKey.coinReward(row.sourceID)]
            valid = valid && partner?.kind == .reward && partner?.createdAt == row.createdAt
        case .reversal:
            let originalKey = RewardLedgerKey.xpReward(row.sourceID)
            guard let original = xp[originalKey], original.kind == .reward, original.amount >= 0 else {
                throw RewardLedgerError.corruptLedger(row.businessKey)
            }
            let partner = coin[RewardLedgerKey.coinReversal(row.sourceID)]
            valid =
                valid && row.businessKey == RewardLedgerKey.xpReversal(row.sourceID)
                && row.reversalOfBusinessKey == originalKey && row.amount == -original.amount
                && row.createdAt >= original.createdAt && partner?.kind == .reversal
                && partner?.createdAt == row.createdAt
        case nil:
            valid = false
        }
        guard valid else { throw RewardLedgerError.corruptLedger(row.businessKey) }
    }

    private static func validate(_ row: CoinTransaction, xp: [String: XPTransaction], coin: [String: CoinTransaction])
        throws
    {
        var valid = row.createdAt.timeIntervalSinceReferenceDate.isFinite
        switch row.kind {
        case .reward:
            valid =
                valid && row.businessKey == RewardLedgerKey.coinReward(row.sourceID)
                && row.amount >= 0 && row.reversalOfBusinessKey == nil
            let partner = xp[RewardLedgerKey.xpReward(row.sourceID)]
            valid = valid && partner?.kind == .reward && partner?.createdAt == row.createdAt
        case .spend:
            valid =
                valid && row.businessKey == RewardLedgerKey.coinSpend(row.sourceID)
                && row.amount < 0 && row.amount != Int.min && row.reversalOfBusinessKey == nil
        case .reversal:
            let originalKey = RewardLedgerKey.coinReward(row.sourceID)
            guard let original = coin[originalKey], original.kind == .reward, original.amount >= 0 else {
                throw RewardLedgerError.corruptLedger(row.businessKey)
            }
            let partner = xp[RewardLedgerKey.xpReversal(row.sourceID)]
            valid =
                valid && row.businessKey == RewardLedgerKey.coinReversal(row.sourceID)
                && row.reversalOfBusinessKey == originalKey && row.amount == -original.amount
                && row.createdAt >= original.createdAt && partner?.kind == .reversal
                && partner?.createdAt == row.createdAt
        case nil:
            valid = false
        }
        guard valid else { throw RewardLedgerError.corruptLedger(row.businessKey) }
    }
}
