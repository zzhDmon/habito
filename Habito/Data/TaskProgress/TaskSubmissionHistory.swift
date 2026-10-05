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
}
