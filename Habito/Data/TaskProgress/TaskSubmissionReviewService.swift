import Foundation
import SwiftData

/// 家长审核原子事务；权限由后续家长组合根/PIN 入口控制，服务不读取凭据或弹界面。
@MainActor
struct TaskSubmissionReviewService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 通过明确的原提交；提交快照、自主性、完成事实和真实审核时刻分别保留。
    ///
    /// - Parameters:
    ///   - occurrence: 同主写上下文中的实例，不支持跨容器活跃对象。
    ///   - submissionID: 请求捕获的提交 ID，不能自动替换成最新一条。
    ///   - now: 注入的真实审核/结算时刻，不能早于提交。
    /// - Returns: 保存后的审核收据；重复原通过含已冲正情形不会重新发奖。
    /// - Throws: 请求不存在、结果冲突、状态/审计损坏、时间倒退、账本溢出或保存失败。
    func approve(_ occurrence: TaskOccurrence, submissionID: UUID, at now: Date) throws -> TaskSubmissionReviewResult {
        try review(occurrence, submissionID: submissionID, state: .approved, at: now)
    }

    /// 退回原提交，不发奖、不删除任何计时或提交历史；之后可以继续计时并重提。
    ///
    /// - Returns: 保存后的退回收据；旧请求重试不修改后来重提的等待事实。
    /// - Throws: 与通过共用请求/历史/时间和保存验证，失败仍保持等待。
    func returnForRevision(_ occurrence: TaskOccurrence, submissionID: UUID, at now: Date) throws
        -> TaskSubmissionReviewResult
    {
        try review(occurrence, submissionID: submissionID, state: .returned, at: now)
    }

    private func review(
        _ occurrence: TaskOccurrence, submissionID: UUID, state: SubmissionReviewState, at now: Date
    ) throws -> TaskSubmissionReviewResult {
        guard occurrence.modelContext === context else { throw TaskCompletionServiceError.modelNotInContext }
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
        let rows = try TaskSubmissionHistory(context: context).records(for: occurrence.id)
        guard let row = rows.first(where: { $0.id == submissionID }) else {
            throw TaskSubmissionReviewError.submissionNotFound(submissionID)
        }
        if row.reviewState != .waiting {
            guard row.reviewState == state else { throw TaskSubmissionReviewError.conflictingOutcome(submissionID) }
            return try result(row, didReview: false)
        }
        let progress = TaskProgressService(context: context)
        let occurrenceID = occurrence.id
        let sessions = try context.fetch(
            FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
        guard rows.last?.id == row.id, occurrence.status == .pending,
            try progress.completionRecord(for: occurrence) == nil,
            sessions.allSatisfy({ $0.state == .ended }),
            try progress.submissionDuration(for: occurrence, at: row.submittedAt) == row.activeDurationSeconds
        else { throw TaskSubmissionReviewError.unavailableState(occurrence.id) }
        guard now >= row.submittedAt else { throw TaskSubmissionReviewError.timeBeforeSubmission(row.id) }
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: row.submittedAt, reminderAt: row.reminderAtSnapshot,
            xp: row.xpRewardSnapshot, baseCoins: row.coinRewardSnapshot,
            autonomyBonusCoins: row.activeBonusCoinSnapshot)
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        let originalStatus = occurrence.statusRawValue
        let originalUpdatedAt = occurrence.updatedAt
        var stagedRecord: CompletionRecord?
        do {
            row.reviewStateRawValue = state.rawValue
            row.reviewedAt = now
            occurrence.updatedAt = now
            if state == .approved {
                // 不走直接完成的等待拒绝入口；只使用已验证的提交冻结时长，不在审核时继续累计。
                let record = CompletionRecord(
                    occurrenceID: occurrence.id, completedAt: row.submittedAt,
                    activeDurationSeconds: row.activeDurationSeconds, completionSource: .parentApproval,
                    createdAt: now, updatedAt: now, completionTiming: snapshot.timing,
                    reminderAtSnapshot: snapshot.reminderAt, xpRewardSnapshot: snapshot.xp,
                    coinRewardSnapshot: snapshot.baseCoins, activeBonusCoinSnapshot: snapshot.autonomyBonusCoins,
                    settledCoinSnapshot: snapshot.settledCoins, rewardSettlementVersion: 2,
                    submissionID: row.id, rewardSettledAt: now)
                context.insert(record)
                stagedRecord = record
                occurrence.completionRecord = record
                record.occurrence = occurrence
                occurrence.statusRawValue = TaskOccurrenceStatus.completed.rawValue
                row.reviewedCompletionID = record.id
                _ = try RewardLedgerService(context: context).stageReward(
                    sourceID: record.id, xp: snapshot.xp, coins: snapshot.settledCoins, at: now)
                _ = try TaskCompletionAuditValidator(context: context).validate(record)
            }
            let receipt = try result(row, didReview: true)
            try saveChanges(context)
            return receipt
        } catch {
            // 17 回滚新双向关系会递归；先断本事务新关系并恢复原标量，不保存任何补偿中间态。
            if let stagedRecord {
                occurrence.completionRecord = nil
                stagedRecord.occurrence = nil
            }
            occurrence.statusRawValue = originalStatus
            occurrence.updatedAt = originalUpdatedAt
            row.reviewStateRawValue = SubmissionReviewState.waiting.rawValue
            row.reviewedAt = nil
            row.reviewedCompletionID = nil
            context.rollback()
            throw error
        }
    }

    private func result(_ row: TaskSubmission, didReview: Bool) throws -> TaskSubmissionReviewResult {
        guard let state = row.reviewState, let reviewedAt = row.reviewedAt, let timing = row.completionTiming else {
            throw TaskSubmissionError.corruptHistory(row.occurrenceID)
        }
        var completion: CompletionRecord?
        if let id = row.reviewedCompletionID {
            completion = try context.fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.id == id }))
                .first
            guard let completion else { throw TaskSubmissionError.corruptHistory(row.occurrenceID) }
            _ = try TaskCompletionAuditValidator(context: context).validate(completion)
        }
        return TaskSubmissionReviewResult(
            submissionID: row.id, state: state, submittedAt: row.submittedAt, reviewedAt: reviewedAt,
            completionID: completion?.id, timing: timing, xp: completion?.xpRewardSnapshot ?? 0,
            coins: completion?.settledCoinSnapshot ?? 0, rewardIsRevoked: completion?.revokedAt != nil,
            didReview: didReview)
    }
}
