import Foundation
import SwiftData

/// 纯值与独立内存预览夹具，不写正式持久化容器；金额仅展示用途，不是默认奖励。
enum ParentReviewPreview {
    static func emptyModel() -> ParentReviewViewModel {
        do {
            let context = ModelContext(try AppModelContainer.make(inMemory: true))
            return ParentReviewViewModel(
                context: context, dateProvider: SystemDateProvider(),
                reviewService: TaskSubmissionReviewService(context: context))
        } catch {
            preconditionFailure("无法创建预览内存容器")
        }
    }

    static var item: ParentReviewQueueItem {
        let date: LocalDate
        do { date = try LocalDate(dateKey: "2026-09-23") } catch { preconditionFailure("预览固定日期无效") }
        return ParentReviewQueueItem(
            id: UUID(), occurrenceID: UUID(), taskDate: date,
            title: String(localized: "parentReview.previewTask"), iconName: "book.fill",
            submittedAt: Date(timeIntervalSince1970: 1_790_136_000),
            reminderAt: Date(timeIntervalSince1970: 1_790_136_060), activeDurationSeconds: 900,
            timing: .beforeReminder, expectedXP: 11, expectedBaseCoins: 7, expectedAutonomyCoins: 3, expectedCoins: 10)
    }

    static func feedback(approved: Bool) -> ParentReviewFeedback {
        let item = item
        return ParentReviewFeedback(
            occurrenceID: item.occurrenceID,
            result: TaskSubmissionReviewResult(
                submissionID: item.id, state: approved ? .approved : .returned,
                submittedAt: item.submittedAt, reviewedAt: item.reminderAt,
                completionID: approved ? UUID() : nil, timing: item.timing,
                xp: approved ? item.expectedXP : 0, coins: approved ? item.expectedCoins : 0,
                rewardIsRevoked: false, didReview: true))
    }
}
