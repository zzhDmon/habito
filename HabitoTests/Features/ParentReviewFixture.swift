import Foundation
import SwiftData
import Testing
@testable import Habito

/// 家长队列仅使用合成数据库与固定时间，不读取正式家庭配置或真实凭据。
@MainActor
struct ParentReviewFixture {
    let context: ModelContext
    let now: Date

    init(storeURL: URL? = nil) throws {
        let container =
            try storeURL.map { try AppModelContainer.make(storeURL: $0) }
            ?? AppModelContainer.make(inMemory: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
        now = try V0MigrationFixture.instant("2026-09-23T04:00:00Z")
    }

    func makeWaiting(
        id: UUID = V0MigrationFixture.pendingID, day: String = "2026-09-23",
        submittedOffset: TimeInterval = 0, zero: Bool = false
    ) throws -> TaskOccurrence {
        let occurrence = TaskOccurrence(
            id: id, templateID: V0MigrationFixture.templateID,
            date: try LocalDate(dateKey: day), scheduledAt: now.addingTimeInterval(60),
            titleSnapshot: "合成待验收", iconSnapshot: "book.fill", colorSnapshot: "reading",
            targetDurationSnapshot: 900, sourceRevision: 1, createdAt: now, updatedAt: now,
            verificationTypeSnapshot: .parentApproval, xpRewardSnapshot: zero ? 0 : 11,
            coinRewardSnapshot: zero ? 0 : 7, activeBonusCoinSnapshot: zero ? 0 : 3)
        context.insert(occurrence)
        try context.save()
        _ = try TaskProgressService(context: context).startTiming(for: occurrence, at: now.addingTimeInterval(-30))
        _ = try TaskSubmissionService(context: context).submit(occurrence, at: now.addingTimeInterval(submittedOffset))
        return occurrence
    }

    func item(for occurrence: TaskOccurrence) throws -> ParentReviewQueueItem {
        let items = try ParentReviewQueueService(context: context).items()
        return try #require(items.first { $0.occurrenceID == occurrence.id })
    }

    func model(
        at date: Date? = nil, trigger: NotificationRebuildTrigger = NotificationRebuildTrigger(),
        shouldFailSave: Bool = false
    ) -> ParentReviewViewModel {
        let service = TaskSubmissionReviewService(
            context: context,
            saveChanges: shouldFailSave
                ? { _ in throw NSError(domain: "HabitoSyntheticParentReviewSave", code: 1) }
                : { try $0.save() })
        return ParentReviewViewModel(
            context: context, dateProvider: FixedDateProvider(value: date ?? now),
            notificationRebuildTrigger: trigger, reviewService: service)
    }

    func items(from model: ParentReviewViewModel) throws -> [ParentReviewQueueItem] {
        guard case let .loaded(items) = model.state else {
            throw NSError(domain: "HabitoSyntheticParentReviewState", code: 1)
        }
        return items
    }

    func expectNoReward() throws {
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }
}
