import Foundation
import SwiftData

/// XP/Coin 唯一业务写入口；同步主 actor 操作中没有 await，不在校验和保存之间让出执行。
///
/// - Important: 同一家庭库由组合根的单一写上下文管理；不支持多个未保存上下文竞争写账。
///   独立方法要求干净上下文。`stage` 方法供后续任务完成/消费事务组合，不自行保存。
@MainActor
struct RewardLedgerService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    /// 保存边界可注入失败替身；正式路径仍使用原生 ModelContext.save，不新增持久化框架。
    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    func balance() throws -> RewardBalance { try RewardLedgerSnapshot(context: context).balance }

    /// 独立结算显式收入，重复来源和相同金额返回原收据，不再次入账。
    ///
    /// - Parameters:
    ///   - sourceID: 本次完成/验收事件 ID，不能使用会再次完成的任务实例 ID。
    ///   - xp: 非负显式 XP；零也保存，以冻结本次事件的输入。
    ///   - coins: 非负显式 Coin，已由调用方合并基础与自主奖励。
    ///   - now: 注入的写入时间；重试不覆盖第一次时间。
    /// - Returns: 保存后的收入收据；幂等重试的 didInsert 为 false，保留原写入时间。
    /// - Throws: 输入无效、账本损坏、幂等冲突、溢出或保存错误。
    func grantReward(sourceID: UUID, xp: Int, coins: Int, at now: Date) throws -> RewardLedgerMutation {
        try commit { try stageReward(sourceID: sourceID, xp: xp, coins: coins, at: now) }
    }

    /// 消费只接受正成本；购买事件 ID 稳定，重复点击不重复扣款。
    func spendCoins(sourceID: UUID, cost: Int, at now: Date) throws -> RewardLedgerMutation {
        try commit { try stageSpend(sourceID: sourceID, cost: cost, at: now) }
    }

    /// 纠错只冲正原收入；余额不足明确拒绝，原收入与已有消费不变。
    func reverseReward(sourceID: UUID, at now: Date) throws -> RewardLedgerMutation {
        try commit { try stageRewardReversal(sourceID: sourceID, at: now) }
    }

    /// 暂存收入，供上层把完成事实与两种资产在一次保存中提交。
    ///
    /// - Important: 调用方必须关闭自动保存、统一保存/失败回滚；返回结果不代表已到账。
    func stageReward(sourceID: UUID, xp: Int, coins: Int, at now: Date) throws -> RewardLedgerMutation {
        guard xp >= 0, coins >= 0 else { throw RewardLedgerError.invalidAmount }
        try validateTime(now)
        let snapshot = try RewardLedgerSnapshot(context: context)
        if let existing = snapshot.xp[RewardLedgerKey.xpReward(sourceID)],
            let partner = snapshot.coin[RewardLedgerKey.coinReward(sourceID)]
        {
            guard existing.amount == xp, partner.amount == coins else {
                throw RewardLedgerError.businessKeyConflict(existing.businessKey)
            }
            return mutation(sourceID, xp: xp, coins: coins, at: existing.createdAt, inserted: false)
        }
        try ensureAddition(snapshot.balance.effectiveXP, xp)
        try ensureAddition(snapshot.balance.coins, coins)
        context.insert(
            XPTransaction(
                businessKey: RewardLedgerKey.xpReward(sourceID), sourceID: sourceID,
                kind: .reward, amount: xp, createdAt: now))
        context.insert(
            CoinTransaction(
                businessKey: RewardLedgerKey.coinReward(sourceID), sourceID: sourceID,
                kind: .reward, amount: coins, createdAt: now))
        return mutation(sourceID, xp: xp, coins: coins, at: now, inserted: true)
    }

    /// 暂存消费；宠物阶段可把互动记录与此扣账一起提交，不先播放成功动画。
    ///
    /// - Important: 返回值仅代表暂存；调用方负责关闭自动保存、统一保存或回滚。
    func stageSpend(sourceID: UUID, cost: Int, at now: Date) throws -> RewardLedgerMutation {
        guard cost > 0 else { throw RewardLedgerError.invalidAmount }
        try validateTime(now)
        let snapshot = try RewardLedgerSnapshot(context: context)
        let key = RewardLedgerKey.coinSpend(sourceID)
        if let existing = snapshot.coin[key] {
            guard existing.amount == -cost else { throw RewardLedgerError.businessKeyConflict(key) }
            return mutation(sourceID, xp: 0, coins: -cost, at: existing.createdAt, inserted: false)
        }
        guard snapshot.balance.coins >= cost else {
            throw RewardLedgerError.insufficientCoins(required: cost, available: snapshot.balance.coins)
        }
        context.insert(
            CoinTransaction(businessKey: key, sourceID: sourceID, kind: .spend, amount: -cost, createdAt: now))
        return mutation(sourceID, xp: 0, coins: -cost, at: now, inserted: true)
    }

    /// 暂存精确反向交易，不删除原事实；上层还需在同一事务中改完成/实例状态。
    ///
    /// - Important: 返回值仅代表暂存；调用方负责关闭自动保存、统一保存或回滚。
    func stageRewardReversal(sourceID: UUID, at now: Date) throws -> RewardLedgerMutation {
        try validateTime(now)
        let snapshot = try RewardLedgerSnapshot(context: context)
        guard let originalXP = snapshot.xp[RewardLedgerKey.xpReward(sourceID)],
            let originalCoin = snapshot.coin[RewardLedgerKey.coinReward(sourceID)]
        else { throw RewardLedgerError.rewardNotFound(sourceID) }
        if let existing = snapshot.xp[RewardLedgerKey.xpReversal(sourceID)] {
            return mutation(
                sourceID, xp: existing.amount, coins: -originalCoin.amount, at: existing.createdAt, inserted: false)
        }
        guard now >= originalXP.createdAt else { throw RewardLedgerError.timeBeforeReward }
        guard snapshot.balance.coins >= originalCoin.amount else {
            throw RewardLedgerError.insufficientCoins(required: originalCoin.amount, available: snapshot.balance.coins)
        }
        context.insert(
            XPTransaction(
                businessKey: RewardLedgerKey.xpReversal(sourceID), sourceID: sourceID,
                kind: .reversal, amount: -originalXP.amount, reversalOfBusinessKey: originalXP.businessKey,
                createdAt: now))
        context.insert(
            CoinTransaction(
                businessKey: RewardLedgerKey.coinReversal(sourceID), sourceID: sourceID,
                kind: .reversal, amount: -originalCoin.amount, reversalOfBusinessKey: originalCoin.businessKey,
                createdAt: now))
        return mutation(sourceID, xp: -originalXP.amount, coins: -originalCoin.amount, at: now, inserted: true)
    }

    private func commit(_ operation: () throws -> RewardLedgerMutation) throws -> RewardLedgerMutation {
        // 干净上下文是回滚边界：不能保存或丢弃用户尚未提交的其他编辑。
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            let result = try operation()
            if result.didInsert { try saveChanges(context) }
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    private func validateTime(_ now: Date) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
    }

    private func ensureAddition(_ current: Int, _ amount: Int) throws {
        guard !current.addingReportingOverflow(amount).overflow else { throw RewardLedgerError.integerOverflow }
    }

    private func mutation(_ sourceID: UUID, xp: Int, coins: Int, at now: Date, inserted: Bool) -> RewardLedgerMutation {
        RewardLedgerMutation(sourceID: sourceID, xpDelta: xp, coinDelta: coins, createdAt: now, didInsert: inserted)
    }
}
