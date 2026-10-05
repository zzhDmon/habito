import Foundation
import SwiftData

/// 在主 actor 内读取并验证审核队列，模型不跨并发域，不读取系统当前时间。
@MainActor
struct ParentReviewQueueService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 返回所有日期的真实待审核提交，按最早提交、所属日期和稳定 ID 排序。
    ///
    /// - Returns: 不持有持久化对象的请求快照；已通过/退回和无提交旧任务不进入队列。
    /// - Throws: 孤儿提交、损坏序列/计时/账本、坏日期或底层读取失败。
    /// - Important: 不先按 waiting 原始字符串过滤，否则损坏状态会被悄悄当成空队列。
    func items() throws -> [ParentReviewQueueItem] {
        let submissions = try context.fetch(FetchDescriptor<TaskSubmission>())
        let occurrenceIDs = Set(submissions.map(\.occurrenceID)).sorted { $0.uuidString < $1.uuidString }
        let history = TaskSubmissionHistory(context: context)
        var items: [ParentReviewQueueItem] = []
        for occurrenceID in occurrenceIDs {
            let occurrence = try occurrence(id: occurrenceID)
            guard let row = try history.latest(for: occurrence), row.reviewState == .waiting else { continue }
            let date: LocalDate
            do {
                date = try LocalDate(dateKey: occurrence.dateKey)
            } catch {
                throw ParentReviewQueueError.invalidTaskDate(occurrence.id, occurrence.dateKey)
            }
            let reward = try CompletionRewardSnapshot(
                submittedAt: row.submittedAt, reminderAt: row.reminderAtSnapshot,
                xp: row.xpRewardSnapshot, baseCoins: row.coinRewardSnapshot,
                autonomyBonusCoins: row.activeBonusCoinSnapshot)
            items.append(
                ParentReviewQueueItem(
                    id: row.id, occurrenceID: occurrence.id, taskDate: date,
                    title: occurrence.titleSnapshot, iconName: occurrence.iconSnapshot,
                    submittedAt: row.submittedAt, reminderAt: row.reminderAtSnapshot,
                    activeDurationSeconds: row.activeDurationSeconds, timing: reward.timing,
                    expectedXP: reward.xp, expectedBaseCoins: reward.baseCoins,
                    expectedAutonomyCoins: reward.settledCoins - reward.baseCoins,
                    expectedCoins: reward.settledCoins))
        }
        return items.sorted {
            ($0.submittedAt, $0.taskDate, $0.id.uuidString) < ($1.submittedAt, $1.taskDate, $1.id.uuidString)
        }
    }

    /// 检查局部反馈是否仍对应最新审核事实；不会从历史记录重建一次庆祝。
    func isCurrent(_ feedback: ParentReviewFeedback) throws -> Bool {
        let occurrence = try occurrence(id: feedback.occurrenceID)
        guard let row = try TaskSubmissionHistory(context: context).latest(for: occurrence),
            row.id == feedback.id, row.reviewState == feedback.result.state
        else { return false }
        switch feedback.result.state {
        case .approved:
            // 冲正之后原审核审计仍保留，但不能让局部结果卡继续宣称本次奖励有效。
            return occurrence.status == .completed
                && occurrence.completionRecord?.id == feedback.result.completionID
                && occurrence.completionRecord?.revokedAt == nil
        case .returned:
            return true
        case .waiting:
            return false
        }
    }

    private func occurrence(id: UUID) throws -> TaskOccurrence {
        let rows = try context.fetch(FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == id }))
        guard let occurrence = rows.first else { throw ParentReviewQueueError.occurrenceNotFound(id) }
        return occurrence
    }
}
