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
