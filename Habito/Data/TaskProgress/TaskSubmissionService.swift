import Foundation
import SwiftData

/// 把提交快照与计时终态一次保存；等待阶段不创建完成或任何 XP/Coin 交易。
@MainActor
struct TaskSubmissionService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 冻结一次家长验收提交；等待重试沿用原事实，退回重提才创建新序号。
    ///
    /// - Parameters:
    ///   - occurrence: 同一主写上下文中的实例。
    ///   - now: 注入的提交绝对时刻，不读取审核或通知送达时刻。
    /// - Returns: 保存后的提交收据，didSubmit 为 false 表示等待事实已存在。
    /// - Throws: 非家长验收、状态/历史损坏、时间倒退或保存错误，失败不半结束计时。
    func submit(_ occurrence: TaskOccurrence, at now: Date) throws -> TaskSubmissionResult {
        guard occurrence.modelContext === context else { throw TaskCompletionServiceError.modelNotInContext }
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
        let rows = try TaskSubmissionHistory(context: context).records(for: occurrence.id)
        let progress = TaskProgressService(context: context)
        guard try progress.completionRecord(for: occurrence) == nil,
            occurrence.status == .pending || occurrence.status == .inProgress
        else { throw TaskSubmissionError.unavailableState(occurrence.id) }
        let occurrenceID = occurrence.id
        let sessions = try context.fetch(
            FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
        if let existing = rows.last, existing.reviewState == .waiting {
            // 不读后来更改的配置；等待重试只验证原终态和原累计时长。
            guard occurrence.status == .pending, sessions.allSatisfy({ $0.state == .ended }) else {
                throw TaskSubmissionError.corruptHistory(occurrence.id)
            }
            let duration = try progress.submissionDuration(for: occurrence, at: existing.submittedAt)
            guard duration == existing.activeDurationSeconds else {
                throw TaskSubmissionError.corruptHistory(occurrence.id)
            }
            return try result(existing, didSubmit: false)
        }
        guard occurrence.verificationTypeSnapshot == .parentApproval else {
            throw TaskSubmissionError.parentApprovalRequired(occurrence.id)
        }
        if let last = rows.last {
            // 审核尚未接入时只能从明确退回重提；已通过不是新的提交许可。
            guard last.reviewState == .returned else { throw TaskSubmissionError.unavailableState(occurrence.id) }
            guard let reviewedAt = last.reviewedAt, now >= reviewedAt else {
                throw TaskSubmissionError.timeBeforePreviousReview(occurrence.id)
            }
        }
        let next = (rows.last?.sequenceNumber ?? 0).addingReportingOverflow(1)
        guard !next.overflow else { throw TaskSubmissionError.sequenceOverflow(occurrence.id) }
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: now, reminderAt: occurrence.scheduledAt, xp: occurrence.xpRewardSnapshot,
            baseCoins: occurrence.coinRewardSnapshot, autonomyBonusCoins: occurrence.activeBonusCoinSnapshot)
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        let originalStatus = occurrence.statusRawValue
        let originalUpdatedAt = occurrence.updatedAt
        let originalSessions = sessions.map { ($0, $0.accumulatedActiveSeconds, $0.stateRawValue, $0.endedAt) }
        do {
            let duration = try progress.stageSubmissionTimingEnd(occurrence, at: now)
            let row = TaskSubmission(
                occurrenceID: occurrence.id, sequenceNumber: next.partialValue,
                snapshot: snapshot, activeDurationSeconds: duration)
            context.insert(row)
            let receipt = try result(row, didSubmit: true)
            try saveChanges(context)
            return receipt
        } catch {
            // 17 的 Swift 层标量缓存需恢复原值，再 rollback 移除插入提交；没有补偿保存。
            occurrence.statusRawValue = originalStatus
            occurrence.updatedAt = originalUpdatedAt
            for (session, accumulated, state, endedAt) in originalSessions {
                session.accumulatedActiveSeconds = accumulated
                session.stateRawValue = state
                session.endedAt = endedAt
            }
            context.rollback()
            throw error
        }
    }

    private func result(_ row: TaskSubmission, didSubmit: Bool) throws -> TaskSubmissionResult {
        guard let timing = row.completionTiming else { throw TaskSubmissionError.corruptHistory(row.occurrenceID) }
        return TaskSubmissionResult(
            submissionID: row.id, submittedAt: row.submittedAt, timing: timing,
            activeDurationSeconds: row.activeDurationSeconds, didSubmit: didSubmit)
    }
}
