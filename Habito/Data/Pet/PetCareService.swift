import Foundation
import SwiftData

/// 单孩子/单宠物的只读成长投影和喂食事务，复用唯一Coin账本，不复制金币余额。
///
/// 主actor同步事务没有await；干净上下文是边界，失败只能回滚本次插入。
@MainActor
struct PetCareService {
    private let context: ModelContext
    private let calendar: Calendar
    private let saveChanges: (ModelContext) throws -> Void

    /// 日界由组合根注入；保存替身只能在实际提交前失败，不能提交成功后再抛错。
    init(
        context: ModelContext, calendar: Calendar, timeZone: TimeZone,
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        self.calendar = localCalendar
        self.saveChanges = saveChanges
    }

    /// 无资料返回nil，不创建记录；已喂食却无完整资料属于坏数据，不能静默吞掉。
    func load(at now: Date) throws -> PetCareSnapshot? {
        try requireCleanContext()
        try validateTime(now)
        let names = try FamilyProfileService(context: context).load()
        let ledger = try RewardLedgerSnapshot(context: context)
        let feedings = try validatedFeedings(ledger: ledger)
        guard let names else {
            guard feedings.isEmpty else { throw PetCareError.invalidFacts }
            return nil
        }
        guard let day = calendar.dateInterval(of: .day, for: now) else { throw PetCareError.invalidTimestamp }
        let xp = ledger.balance.effectiveXP
        return PetCareSnapshot(
            names: names, effectiveXP: xp, level: try PetCareRules.level(effectiveXP: xp),
            xpInLevel: xp % PetCareRules.xpPerLevel,
            xpToNextLevel: PetCareRules.xpPerLevel - xp % PetCareRules.xpPerLevel,
            coins: ledger.balance.coins, bond: try RewardBalance.checkedTotal(feedings.map(\.bondGain)),
            mood: feedings.contains { $0.createdAt >= day.start && $0.createdAt < day.end && $0.createdAt <= now }
                ? .happy : .calm)
    }

    /// 同请求ID重试不重复扣款；Coin消费与喂食事实同一次save，失败不增加Bond。
    /// - Parameters:
    ///   - requestID: 一次用户意图的稳定ID；失败重试必须复用，下一次明确喂食才新建。
    ///   - now: 注入时刻。重复请求保留第一次时刻，新请求拒绝早于已有喂食的时间。
    /// - Returns: 已保存事实收据；幂等重试的didInsert为false。
    /// - Throws: 未配置、损坏事实、幂等冲突、时间逆序、余额不足、脏上下文或保存错误。
    func feed(requestID: UUID, at now: Date) throws -> PetFeedingReceipt {
        guard let snapshot = try load(at: now) else { throw PetCareError.notConfigured }
        let ledger = try RewardLedgerSnapshot(context: context)
        let rows = try validatedFeedings(ledger: ledger)
        if let existing = rows.first(where: { $0.id == requestID }) {
            return receipt(existing, inserted: false)
        }
        // 已有扣款却没有配对喂食不能补写“修复”，否则可能侵占另一种消费的幂等键。
        guard ledger.coin[RewardLedgerKey.coinSpend(requestID)] == nil else { throw PetCareError.feedingConflict }
        guard !rows.contains(where: { $0.createdAt > now }) else { throw PetCareError.timeBeforeLatestFeeding }
        _ = try RewardBalance.checkedTotal([snapshot.bond, PetCareRules.feedingBondGain])
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            _ = try RewardLedgerService(context: context).stageSpend(
                sourceID: requestID, cost: PetCareRules.foodCost, at: now)
            let feeding = PetFeeding(
                id: requestID, petKey: Pet.defaultKey, foodID: PetCareRules.foodID,
                coinCost: PetCareRules.foodCost, bondGain: PetCareRules.feedingBondGain, createdAt: now)
            context.insert(feeding)
            try saveChanges(context)
            return receipt(feeding, inserted: true)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func validatedFeedings(ledger: RewardLedgerSnapshot) throws -> [PetFeeding] {
        let rows = try context.fetch(FetchDescriptor<PetFeeding>())
        var ids: Set<UUID> = []
        for row in rows {
            guard ids.insert(row.id).inserted, row.petKey == Pet.defaultKey,
                row.foodID == PetCareRules.foodID, row.coinCost == PetCareRules.foodCost,
                row.bondGain == PetCareRules.feedingBondGain,
                row.createdAt.timeIntervalSinceReferenceDate.isFinite,
                let spend = ledger.coin[RewardLedgerKey.coinSpend(row.id)], spend.kind == .spend,
                spend.amount == -row.coinCost, spend.createdAt == row.createdAt
            else { throw PetCareError.invalidFacts }
        }
        return rows
    }

    private func requireCleanContext() throws {
        guard !context.hasChanges else { throw PetCareError.pendingContextChanges }
    }

    private func validateTime(_ now: Date) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw PetCareError.invalidTimestamp }
    }

    private func receipt(_ row: PetFeeding, inserted: Bool) -> PetFeedingReceipt {
        PetFeedingReceipt(
            id: row.id, coinCost: row.coinCost, bondGain: row.bondGain, createdAt: row.createdAt, didInsert: inserted)
    }
}
