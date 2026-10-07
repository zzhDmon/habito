import Foundation
import SwiftData

/// 在主 actor 查询真实审核收据并确认已读；不结算奖励、不读取系统时间、不接触通知。
///
/// - Note: 旧历史版本 0 不推断投递资格。已读只由孩子明确继续/关闭调用，查询本身不写库。
@MainActor
struct ChildRewardReceiptService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    /// 从组合根注入主写上下文与保存边界；测试可模拟保存失败，不引入新的数据库或后台上下文。
    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 不按业务日期过滤：次日通过仍应反馈原任务，按到账时刻和稳定 ID 顺序返回。
    ///
    /// - Returns: 未撤销且未确认的真实收据；零奖励仍保留努力事实。
    /// - Throws: 未保存编辑、投递元数据、完成审计或账本损坏；不保存或回滚调用方编辑。
    func pendingReceipts() throws -> [ChildRewardReceipt] {
        try requireCleanContext()
        let records = try context.fetch(FetchDescriptor<CompletionRecord>())
        var receipts: [ChildRewardReceipt] = []
        for record in records {
            guard try validateDelivery(record) else { continue }
            _ = try TaskCompletionAuditValidator(context: context).validate(record)
            guard record.revokedAt == nil, record.childFeedbackAcknowledgedAt == nil else { continue }
            receipts.append(try receipt(for: record))
        }
        return receipts.sorted {
            if $0.settledAt != $1.settledAt { return $0.settledAt < $1.settledAt }
            return $0.completionID.uuidString < $1.completionID.uuidString
        }
    }

    /// 以完成 ID 确认同一收据；重复确认不改第一次时刻，也不触发第二次保存。
    ///
    /// - Parameters:
    ///   - completionID: 页面捕获的原完成 ID，不能替换为最新一轮完成。
    ///   - now: 注入的确认时刻，有限且不早于真实到账。
    /// - Returns: 本次是否首次保存已读。
    /// - Throws: 收据不存在/不可用、脏上下文、无效时间、损坏审计或保存失败。失败仍可再次查询。
    @discardableResult
    func acknowledge(completionID: UUID, at now: Date) throws -> Bool {
        try requireCleanContext()
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
        guard
            let record = try context.fetch(
                FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.id == completionID })
            ).first
        else { throw ChildRewardReceiptError.completionNotFound(completionID) }
        guard try validateDelivery(record) else { throw ChildRewardReceiptError.unavailableReceipt(completionID) }
        _ = try TaskCompletionAuditValidator(context: context).validate(record)
        guard record.revokedAt == nil else { throw ChildRewardReceiptError.unavailableReceipt(completionID) }
        let receipt = try receipt(for: record)
        guard now >= receipt.settledAt else {
            throw ChildRewardReceiptError.acknowledgementBeforeSettlement(completionID)
        }
        guard record.childFeedbackAcknowledgedAt == nil else { return false }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            record.childFeedbackAcknowledgedAt = now
            try saveChanges(context)
            return true
        } catch {
            // 先恢复标量，兼容 17 的活跃模型缓存；只回滚本用例已确认干净的上下文。
            record.childFeedbackAcknowledgedAt = nil
            context.rollback()
            throw error
        }
    }

    private func requireCleanContext() throws {
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
    }

    /// 元数据不代替账本审计；未知版本或旧记录被写已读都应明确报错，而不是静默当成已展示。
    private func validateDelivery(_ record: CompletionRecord) throws -> Bool {
        if record.childFeedbackDeliveryVersion == 0 {
            guard record.childFeedbackAcknowledgedAt == nil else {
                throw ChildRewardReceiptError.invalidDeliveryMetadata(record.id)
            }
            return false
        }
        guard record.childFeedbackDeliveryVersion == 1, record.completionSource == .parentApproval,
            record.rewardSettlementVersion == 2, let settledAt = record.rewardSettledAt,
            settledAt.timeIntervalSinceReferenceDate.isFinite,
            record.childFeedbackAcknowledgedAt.map({
                $0.timeIntervalSinceReferenceDate.isFinite && $0 >= settledAt
            }) ?? true
        else { throw ChildRewardReceiptError.invalidDeliveryMetadata(record.id) }
        return true
    }

    private func receipt(for record: CompletionRecord) throws -> ChildRewardReceipt {
        guard let occurrence = record.occurrence, let settledAt = record.rewardSettledAt,
            let timing = record.completionTiming
        else { throw ChildRewardReceiptError.unavailableReceipt(record.id) }
        return ChildRewardReceipt(
            completionID: record.id, occurrenceID: record.occurrenceID, title: occurrence.titleSnapshot,
            completedAt: record.completedAt, settledAt: settledAt, timing: timing,
            xp: record.xpRewardSnapshot, coins: record.settledCoinSnapshot)
    }
}
