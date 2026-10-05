import Foundation
import SwiftData

/// 保留记录式撤销：事实、任务状态与奖励冲正一起保存，原消费永不删除。
@MainActor
struct TaskCompletionUndoService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 撤销明确的完成事件；重复旧请求不会撤销后来重新完成的新事件。
    ///
    /// - Parameters:
    ///   - occurrence: 同上下文的目标任务。
    ///   - completionID: 按钮/请求捕获的原完成 ID，不从最新页面状态替换该 ID。
    ///   - now: 注入的绝对请求时间，首次撤销须在五秒窗口内。
    /// - Returns: 保存后的反向收据；已撤销重试 didUndo 为 false，保留原时间。
    /// - Throws: 窗口关闭、余额不足、状态不一致、脏上下文或保存失败，不能半撤销。
    func undo(_ occurrence: TaskOccurrence, completionID: UUID, at now: Date) throws -> TaskCompletionUndoResult {
        guard occurrence.modelContext === context else { throw TaskCompletionServiceError.modelNotInContext }
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
        let occurrenceID = occurrence.id
        let record = try context.fetch(
            FetchDescriptor<CompletionRecord>(
                predicate: #Predicate { $0.occurrenceID == occurrenceID && $0.id == completionID }
            )
        ).first
        guard let record else { throw TaskCompletionUndoError.completionNotFound(completionID) }
        let ledger = try TaskCompletionAuditValidator(context: context).validate(record)
        let originalXP = ledger.xp[RewardLedgerKey.xpReward(record.id)]?.amount ?? 0
        let originalCoin = ledger.coin[RewardLedgerKey.coinReward(record.id)]?.amount ?? 0
        if let revokedAt = record.revokedAt {
            return receipt(record.id, revokedAt: revokedAt, xp: -originalXP, coins: -originalCoin, didUndo: false)
        }
        let progress = TaskProgressService(context: context)
        guard occurrence.status == .completed, try progress.completionRecord(for: occurrence)?.id == record.id else {
            throw TaskCompletionUndoError.completionNotCurrent(record.id)
        }
        guard now >= record.completedAt else {
            throw TaskProgressServiceError.timeBeforeCompletion(occurrenceID: occurrence.id)
        }
        guard CompletionUndoPolicy.canUndo(completedAt: record.completedAt, now: now) else {
            throw TaskCompletionUndoError.undoWindowExpired(record.id)
        }
        let sessions = try context.fetch(
            FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
        for session in sessions {
            guard session.state == .ended else {
                throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(occurrenceID: occurrence.id)
            }
            guard try progress.activeDuration(of: session, at: now).isFinite else {
                throw TaskCompletionServiceError.invalidDuration(occurrence.id)
            }
        }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        let originalStatus = occurrence.statusRawValue
        let originalOccurrenceUpdatedAt = occurrence.updatedAt
        let originalRecordUpdatedAt = record.updatedAt
        let originalRecordOccurrence = record.occurrence
        let originalCompletion = occurrence.completionRecord
        var stagedState = false
        do {
            // 旧零奖励且没有原交易时不捏造冲正；有明确原交易才精确反向。
            if ledger.xp[RewardLedgerKey.xpReward(record.id)] != nil {
                _ = try RewardLedgerService(context: context).stageRewardReversal(sourceID: record.id, at: now)
            }
            stagedState = true
            record.revokedAt = now
            record.updatedAt = now
            occurrence.completionRecord = nil
            record.occurrence = nil
            occurrence.statusRawValue = try TaskOccurrenceStatus.completed.applying(.undoCompletion).rawValue
            occurrence.updatedAt = now
            let result = receipt(record.id, revokedAt: now, xp: -originalXP, coins: -originalCoin, didUndo: true)
            try saveChanges(context)
            return result
        } catch {
            if stagedState {
                // 与完成路径一样，17 的标量缓存需显式恢复；不做补偿 save。
                record.revokedAt = nil
                record.updatedAt = originalRecordUpdatedAt
                occurrence.statusRawValue = originalStatus
                occurrence.updatedAt = originalOccurrenceUpdatedAt
                occurrence.completionRecord = originalCompletion
                record.occurrence = originalRecordOccurrence
            }
            context.rollback()
            throw error
        }
    }

    private func receipt(_ id: UUID, revokedAt: Date, xp: Int, coins: Int, didUndo: Bool) -> TaskCompletionUndoResult {
        TaskCompletionUndoResult(
            completionID: id, revokedAt: revokedAt, xpDelta: xp, coinDelta: coins, didUndo: didUndo)
    }
}
