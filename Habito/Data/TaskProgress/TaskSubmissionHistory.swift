import Foundation
import SwiftData

/// 主 actor 内验证一次实例的提交序列，供提交幂等和其他写入口共享等待保护。
@MainActor
struct TaskSubmissionHistory {
    let context: ModelContext

    /// 返回完整已验证序列，不用某一条合法记录掩盖损坏或多个等待事实。
    func records(for occurrenceID: UUID) throws -> [TaskSubmission] {
        let rows = try context.fetch(
            FetchDescriptor<TaskSubmission>(
                predicate: #Predicate { $0.occurrenceID == occurrenceID },
                sortBy: [SortDescriptor(\.sequenceNumber)]))
        var ids: Set<UUID> = []
        var previousReviewAt: Date?
        let completions = try context.fetch(
            FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
        for (index, row) in rows.enumerated() {
            guard row.sequenceNumber == index + 1, ids.insert(row.id).inserted,
                row.businessKey
                    == TaskSubmission.makeBusinessKey(occurrenceID: occurrenceID, sequenceNumber: row.sequenceNumber),
                row.activeDurationSeconds.isFinite, row.activeDurationSeconds >= 0,
                let state = row.reviewState
            else { throw TaskSubmissionError.corruptHistory(occurrenceID) }
            let snapshot = try CompletionRewardSnapshot(
                submittedAt: row.submittedAt, reminderAt: row.reminderAtSnapshot,
                xp: row.xpRewardSnapshot, baseCoins: row.coinRewardSnapshot,
                autonomyBonusCoins: row.activeBonusCoinSnapshot)
            guard row.completionTiming == snapshot.timing else {
                throw TaskSubmissionError.corruptHistory(occurrenceID)
            }
            if let previousReviewAt, row.submittedAt < previousReviewAt {
                throw TaskSubmissionError.corruptHistory(occurrenceID)
            }
            switch state {
            case .waiting:
                guard index == rows.count - 1, row.reviewedAt == nil, row.reviewedCompletionID == nil else {
                    throw TaskSubmissionError.corruptHistory(occurrenceID)
                }
            case .approved, .returned:
                guard let reviewedAt = row.reviewedAt,
                    reviewedAt.timeIntervalSinceReferenceDate.isFinite, reviewedAt >= row.submittedAt,
                    (state == .approved) == (row.reviewedCompletionID != nil)
                else { throw TaskSubmissionError.corruptHistory(occurrenceID) }
                previousReviewAt = reviewedAt
            }
            let linked = completions.filter { $0.submissionID == row.id }
            if state == .approved {
                guard linked.count == 1, let completion = linked.first,
                    completion.id == row.reviewedCompletionID, completion.rewardSettlementVersion == 2
                else { throw TaskSubmissionError.corruptHistory(occurrenceID) }
                _ = try TaskCompletionAuditValidator(context: context).validate(completion)
                // 已通过只有撤销后才允许后继提交；不能靠伪造第二条等待事实再次领同一奖励。
                if index < rows.count - 1, completion.revokedAt == nil {
                    throw TaskSubmissionError.corruptHistory(occurrenceID)
                }
                if let revokedAt = completion.revokedAt { previousReviewAt = revokedAt }
            } else if !linked.isEmpty {
                throw TaskSubmissionError.corruptHistory(occurrenceID)
            }
        }
        guard completions.allSatisfy({ $0.submissionID.map(ids.contains) ?? true }) else {
            throw TaskSubmissionError.corruptHistory(occurrenceID)
        }
        return rows
    }

    /// 等待事实存在时，任何计时/完成/稍后入口都应明确拒绝，不把 pending 原始值当作许可。
    func requireNotWaiting(_ occurrenceID: UUID) throws {
        if try records(for: occurrenceID).last?.reviewState == .waiting {
            throw TaskSubmissionError.awaitingReview(occurrenceID)
        }
    }

    /// 验证等待确实对应停止计时、未确认完成的实例，供原服务保护和页面查询共用。
    ///
    /// - Returns: 主 actor 内的最新审计记录；无提交时为空，不回填旧历史。
    /// - Throws: 等待与任务/计时事实不一致；不能仅凭 pending 状态推断可操作。
    func latest(for occurrence: TaskOccurrence) throws -> TaskSubmission? {
        guard occurrence.modelContext === context else { throw TaskCompletionServiceError.modelNotInContext }
        let row = try records(for: occurrence.id).last
        if let row, row.reviewState == .waiting {
            let occurrenceID = occurrence.id
            let sessions = try context.fetch(
                FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
            let progress = TaskProgressService(context: context)
            guard occurrence.status == .pending, try progress.completionRecord(for: occurrence) == nil,
                sessions.allSatisfy({ $0.state == .ended }),
                try progress.submissionDuration(for: occurrence, at: row.submittedAt) == row.activeDurationSeconds
            else { throw TaskSubmissionError.corruptHistory(occurrence.id) }
        }
        return row
    }

    /// V1 审计实例不能物理删除；退回或冲正不等于从未发生过提交/完成。
    ///
    /// - Note: 旧 V0 维护性删除夹具仍验证原对象图清理；普通 UI 的历史日期/完成状态保护不变。
    func preservesOccurrenceHistory(_ occurrence: TaskOccurrence) throws -> Bool {
        if try latest(for: occurrence) != nil { return true }
        let occurrenceID = occurrence.id
        return try context.fetchCount(
            FetchDescriptor<CompletionRecord>(
                predicate: #Predicate { $0.occurrenceID == occurrenceID && $0.rewardSettlementVersion > 0 })) > 0
    }

    /// 构造不持有 SwiftData 对象的只读值，预期奖励不得用作“已到账”反馈。
    ///
    /// - Returns: 最新提交快照，旧实例没有提交时为空。
    /// - Throws: 与 latest 共用完整事实验证，不静默隐藏坏等待关系。
    func snapshot(for occurrence: TaskOccurrence) throws -> TaskSubmissionSnapshot? {
        guard let row = try latest(for: occurrence), let state = row.reviewState,
            let timing = row.completionTiming
        else { return nil }
        let reward = try CompletionRewardSnapshot(
            submittedAt: row.submittedAt, reminderAt: row.reminderAtSnapshot,
            xp: row.xpRewardSnapshot, baseCoins: row.coinRewardSnapshot, autonomyBonusCoins: row.activeBonusCoinSnapshot
        )
        return TaskSubmissionSnapshot(
            id: row.id, submittedAt: row.submittedAt, state: state, reviewedAt: row.reviewedAt,
            timing: timing, activeDurationSeconds: row.activeDurationSeconds,
            expectedXP: reward.xp, expectedCoins: reward.settledCoins)
    }
}
