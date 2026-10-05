import Foundation
import SwiftData

/// 自行确认原子事务：计时终态、完成快照、XP 和 Coin 同时保存，失败同时回滚。
///
/// 暂不用于正式 App 入口，须等审计撤销与查询/通知集成完成后统一切换。
@MainActor
struct TaskCompletionService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    /// 注入保存边界便于验证失败；与账本共享同一主 actor 上下文，不引入跨容器活跃对象。
    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 完成自行确认任务；重试返回原收据，旧完成历史不补发奖励。
    ///
    /// - Parameters:
    ///   - occurrence: 同上下文中持久化的目标任务实例。
    ///   - now: 注入的本次提交时间，不取实际通知送达时间。
    ///   - source: 沿用孩子手动或家长更正来源；不会以来源改写统一时间判定。
    /// - Returns: 保存后的稳定收据，didComplete 为 false 表示已有事实，不应重复庆祝。
    /// - Throws: 非自行确认、损坏、金额/时间无效、余额溢出或保存错误，状态不半成功。
    func complete(_ occurrence: TaskOccurrence, at now: Date, source: CompletionSource) throws -> TaskCompletionResult {
        guard occurrence.modelContext === context else { throw TaskCompletionServiceError.modelNotInContext }
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        let originalStatus = occurrence.statusRawValue
        let originalUpdatedAt = occurrence.updatedAt
        let occurrenceID = occurrence.id
        let originalSessions = try context.fetch(
            FetchDescriptor<TimerSession>(
                predicate: #Predicate { $0.occurrenceID == occurrenceID }
            )
        ).map { ($0, $0.accumulatedActiveSeconds, $0.stateRawValue, $0.endedAt) }
        var stagedRecord: CompletionRecord?
        do {
            let progress = TaskProgressService(context: context)
            if let existing = try progress.completionRecord(for: occurrence), occurrence.status == .completed {
                // 先由计时服务验证状态一致性；不读取当前奖励配置来重解释原提交。
                _ = try progress.stageCompletion(occurrence, at: now, source: source)
                try validateExisting(existing)
                return try result(existing, didComplete: false)
            }
            guard let verification = occurrence.verificationTypeSnapshot else {
                throw TaskCompletionServiceError.invalidConfiguration(occurrence.id)
            }
            guard verification == .selfConfirm else {
                throw TaskCompletionServiceError.requiresParentApproval(occurrence.id)
            }
            let snapshot = try CompletionRewardSnapshot(
                submittedAt: now, reminderAt: occurrence.scheduledAt,
                xp: occurrence.xpRewardSnapshot, baseCoins: occurrence.coinRewardSnapshot,
                autonomyBonusCoins: occurrence.activeBonusCoinSnapshot)
            let record = try progress.stageCompletion(occurrence, at: now, source: source, rewardSnapshot: snapshot)
            stagedRecord = record
            _ = try RewardLedgerService(context: context).stageReward(
                sourceID: record.id, xp: snapshot.xp, coins: snapshot.settledCoins, at: now)
            let receipt = try result(record, didComplete: true)
            try saveChanges(context)
            return receipt
        } catch {
            // iPadOS 17 回滚新插入的双向完成关系会递归恢复图并栈溢出。
            // 自动保存已关闭，先断开本事务的新关系，再由 rollback 移除插入行。
            // 不触碰重试命中的既有完成事实，也不额外保存“修复”中间态。
            if let stagedRecord {
                occurrence.completionRecord = nil
                stagedRecord.occurrence = nil
                // 旧 runtime 不总会同步恢复 Swift 层标量缓存；先恢复本事务实际修改的字段，
                // 再回滚持久化边界。没有补偿性 save，也不会覆盖其他用户未提交编辑。
                occurrence.statusRawValue = originalStatus
                occurrence.updatedAt = originalUpdatedAt
                for (session, accumulated, state, endedAt) in originalSessions {
                    session.accumulatedActiveSeconds = accumulated
                    session.stateRawValue = state
                    session.endedAt = endedAt
                }
            }
            context.rollback()
            throw error
        }
    }

    private func validateExisting(_ record: CompletionRecord) throws {
        guard record.revokedAt == nil, record.completionSource != nil, record.completionTiming != nil,
            record.completedAt.timeIntervalSinceReferenceDate.isFinite,
            record.activeDurationSeconds.isFinite, record.activeDurationSeconds >= 0
        else { throw TaskCompletionServiceError.invalidStoredCompletion(record.id) }
        // 迁移旧完成只保留事实，不尝试从当前任务或已有账本补写新快照。
        if record.rewardSettlementVersion == 0 { return }
        guard record.rewardSettlementVersion == 1, let reminderAt = record.reminderAtSnapshot else {
            throw TaskCompletionServiceError.invalidStoredCompletion(record.id)
        }
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: record.completedAt, reminderAt: reminderAt,
            xp: record.xpRewardSnapshot, baseCoins: record.coinRewardSnapshot,
            autonomyBonusCoins: record.activeBonusCoinSnapshot)
        let ledger = try RewardLedgerSnapshot(context: context)
        guard record.completionTiming == snapshot.timing, record.settledCoinSnapshot == snapshot.settledCoins,
            let xp = ledger.xp[RewardLedgerKey.xpReward(record.id)],
            let coin = ledger.coin[RewardLedgerKey.coinReward(record.id)],
            xp.amount == snapshot.xp, coin.amount == snapshot.settledCoins,
            xp.createdAt == record.completedAt, coin.createdAt == record.completedAt,
            ledger.xp[RewardLedgerKey.xpReversal(record.id)] == nil
        else { throw TaskCompletionServiceError.invalidStoredCompletion(record.id) }
    }

    private func result(_ record: CompletionRecord, didComplete: Bool) throws -> TaskCompletionResult {
        guard let timing = record.completionTiming else {
            throw TaskCompletionServiceError.invalidStoredCompletion(record.id)
        }
        return TaskCompletionResult(
            completionID: record.id, completedAt: record.completedAt, timing: timing,
            xp: record.rewardSettlementVersion == 1 ? record.xpRewardSnapshot : 0,
            coins: record.rewardSettlementVersion == 1 ? record.settledCoinSnapshot : 0, didComplete: didComplete)
    }
}
