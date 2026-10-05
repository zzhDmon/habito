import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("提交审计兼容迁移")
struct SubmissionAuditMigrationTests {
    @Test("独立四版旧库迁移与重开，新增提交为空且不回填完成关联", arguments: [0, 1, 2, 3])
    func previousStoresKeepFactsWithoutInventingSubmissions(version: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        switch version {
        case 0: try V0MigrationFixture.seed(at: url)
        case 1: try V1MigrationFixture.seed(at: url)
        case 2: try V2MigrationFixture.seed(at: url)
        default: try V3MigrationFixture.seed(at: url)
        }
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
            let records = try context.fetch(FetchDescriptor<CompletionRecord>())
            #expect(records.count == (version == 0 || version == 3 ? 2 : 1))
            #expect(records.allSatisfy { $0.submissionID == nil && $0.rewardSettledAt == nil })
            let occurrence = try #require(
                context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.id == V0MigrationFixture.completedID })
            #expect(occurrence.status == .completed && occurrence.templateID == V0MigrationFixture.templateID)
            let originalCompletionID =
                version == 0
                ? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4)) : V0MigrationFixture.orphanID
            #expect(occurrence.completionRecord?.id == originalCompletionID)
            #expect(occurrence.completionRecord?.occurrence?.id == occurrence.id)
            let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
            #expect(settings.hasParentPIN && settings.parentPINCredentialKey == "habito.parent-pin")
            #expect(
                try context.fetchCount(FetchDescriptor<XPTransaction>()) == (version == 3 ? 3 : version == 2 ? 1 : 0))
            #expect(
                try context.fetchCount(FetchDescriptor<CoinTransaction>()) == (version == 3 ? 3 : version == 2 ? 1 : 0))
            if version == 3 {
                let current = try #require(records.first { $0.id == V0MigrationFixture.orphanID })
                let old = try #require(records.first { $0.id == V0MigrationFixture.activeID })
                #expect(current.rewardSettlementVersion == 1 && current.settledCoinSnapshot == 10)
                #expect(
                    current.xpRewardSnapshot == 11 && current.coinRewardSnapshot == 7
                        && current.activeBonusCoinSnapshot == 3)
                #expect(current.completedAt == (try V0MigrationFixture.instant("2026-09-22T11:29:00Z")))
                #expect(old.revokedAt == (try V0MigrationFixture.instant("2026-09-22T11:28:01Z")))
                #expect(old.occurrence == nil && old.activeDurationSeconds == 600)
                _ = try TaskCompletionAuditValidator(context: context).validate(current)
                _ = try TaskCompletionAuditValidator(context: context).validate(old)
                #expect(
                    try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
                let xpIDs = try context.fetch(FetchDescriptor<XPTransaction>()).map(\.id)
                let coinIDs = try context.fetch(FetchDescriptor<CoinTransaction>()).map(\.id)
                #expect(
                    Set(xpIDs) == [
                        V0MigrationFixture.activeID, V0MigrationFixture.pendingID, V0MigrationFixture.completedID,
                    ])
                #expect(
                    Set(coinIDs) == [
                        V0MigrationFixture.orphanID, V0MigrationFixture.completedID, V0MigrationFixture.activeID,
                    ])
                let timer = try #require(context.fetch(FetchDescriptor<TimerSession>()).first)
                #expect(timer.id == V3MigrationFixture.pausedSessionID && timer.state == .paused)
                #expect(timer.accumulatedActiveSeconds == 30 && timer.occurrence?.id == V0MigrationFixture.pendingID)
            }
        }
    }

    @Test("独立空结构四迁移保持空提交与空账本")
    func emptyVersionFourStoreMigratesWithoutData() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try seedEmptyVersionFour(at: url)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        }
    }

    @Test("多次提交冻结快照与审核关联可重开，不按后来配置重算或发奖")
    func submissionSnapshotsAndCompletionLinksSurviveReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try seedSyntheticSubmissions(at: url)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let rows = try context.fetch(FetchDescriptor<TaskSubmission>(sortBy: [SortDescriptor(\.sequenceNumber)]))
            #expect(rows.count == 2 && rows.map(\.sequenceNumber) == [1, 2])
            let first = try #require(rows.first)
            let second = try #require(rows.last)
            #expect(first.reviewState == .returned && first.xpRewardSnapshot == 11 && first.coinRewardSnapshot == 7)
            #expect(first.completionTiming == .beforeReminder && first.activeDurationSeconds == 30)
            #expect(second.reviewState == .approved && second.xpRewardSnapshot == 13 && second.coinRewardSnapshot == 9)
            #expect(second.completionTiming == .afterReminder && second.activeDurationSeconds == 40)
            #expect(Set(rows.map(\.businessKey)).count == 2)
            let completion = try #require(context.fetch(FetchDescriptor<CompletionRecord>()).first)
            #expect(completion.submissionID == second.id && second.reviewedCompletionID == completion.id)
            #expect(completion.completedAt == second.submittedAt && completion.rewardSettledAt == second.reviewedAt)
            #expect(completion.rewardSettledAt == (try V0MigrationFixture.instant("2026-09-23T04:00:00Z")))
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
            // 此处只验证结构，不冒充通过/结算事务；后续审核用例负责一致性与原子保存。
        }
    }

    @Test("相同提交时刻用序号区分历史，实例删除不级联抹掉审核审计")
    func equalTimestampsKeepOrderedHistoryWithoutCascade() throws {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: now, reminderAt: now.addingTimeInterval(60), xp: 0, baseCoins: 0, autonomyBonusCoins: 0)
        let occurrence = try makeOccurrence(at: now)
        context.insert(occurrence)
        context.insert(
            TaskSubmission(
                occurrenceID: occurrence.id, sequenceNumber: 1, snapshot: snapshot,
                activeDurationSeconds: 0, reviewState: .returned, reviewedAt: now))
        context.insert(
            TaskSubmission(
                occurrenceID: occurrence.id, sequenceNumber: 2, snapshot: snapshot,
                activeDurationSeconds: 0))
        try context.save()
        context.delete(occurrence)
        try context.save()
        let rows = try context.fetch(FetchDescriptor<TaskSubmission>(sortBy: [SortDescriptor(\.sequenceNumber)]))
        #expect(rows.map(\.sequenceNumber) == [1, 2] && rows.allSatisfy { $0.submittedAt == now })
        #expect(rows.allSatisfy { $0.occurrenceID == V0MigrationFixture.completedID })
    }

    @Test("等待提交重开保持未审核且无完成或到账，零奖励仍记录自主性")
    func waitingSubmissionSurvivesWithoutCompletionOrReward() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try seedWaitingSubmission(at: url)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let row = try #require(context.fetch(FetchDescriptor<TaskSubmission>()).first)
            #expect(row.id == V0MigrationFixture.pendingID && row.sequenceNumber == 1 && row.reviewState == .waiting)
            #expect(row.reviewedAt == nil && row.reviewedCompletionID == nil)
            #expect(row.xpRewardSnapshot == 0 && row.coinRewardSnapshot == 0 && row.completionTiming == .beforeReminder)
            #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
            let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            #expect(occurrence.status == .pending && occurrence.verificationTypeSnapshot == .parentApproval)
        }
    }

    private func seedWaitingSubmission(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let occurrence = try makeOccurrence(at: now)
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: now, reminderAt: now.addingTimeInterval(60), xp: 0, baseCoins: 0, autonomyBonusCoins: 0)
        context.insert(occurrence)
        context.insert(
            TaskSubmission(
                id: V0MigrationFixture.pendingID, occurrenceID: occurrence.id,
                sequenceNumber: 1, snapshot: snapshot, activeDurationSeconds: 0))
        try context.save()
    }

    private func seedEmptyVersionFour(at url: URL) throws {
        let schema = Schema(versionedSchema: HabitoSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        try context.save()
    }

    private func makeOccurrence(at now: Date) throws -> TaskOccurrence {
        TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: V0MigrationFixture.templateID,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: now,
            titleSnapshot: "合成提交", iconSnapshot: "book.fill", colorSnapshot: "reading",
            targetDurationSnapshot: 900, sourceRevision: 1, createdAt: now, updatedAt: now,
            verificationTypeSnapshot: .parentApproval)
    }

    private func seedSyntheticSubmissions(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let reviewedAt = try V0MigrationFixture.instant("2026-09-23T04:00:00Z")
        let occurrence = try makeOccurrence(at: now)
        let first = TaskSubmission(
            id: V0MigrationFixture.pendingID, occurrenceID: occurrence.id, sequenceNumber: 1,
            snapshot: try CompletionRewardSnapshot(
                submittedAt: now, reminderAt: now.addingTimeInterval(60),
                xp: 11, baseCoins: 7, autonomyBonusCoins: 3), activeDurationSeconds: 30,
            reviewState: .returned, reviewedAt: now.addingTimeInterval(60))
        let second = TaskSubmission(
            id: V3MigrationFixture.pausedSessionID, occurrenceID: occurrence.id, sequenceNumber: 2,
            snapshot: try CompletionRewardSnapshot(
                submittedAt: now.addingTimeInterval(120), reminderAt: now.addingTimeInterval(60),
                xp: 13, baseCoins: 9, autonomyBonusCoins: 4), activeDurationSeconds: 40,
            reviewState: .approved, reviewedAt: reviewedAt, reviewedCompletionID: V0MigrationFixture.orphanID)
        let completion = CompletionRecord(
            id: V0MigrationFixture.orphanID, occurrenceID: occurrence.id,
            completedAt: second.submittedAt, activeDurationSeconds: 40, completionSource: .parentCorrection,
            createdAt: reviewedAt, updatedAt: reviewedAt, submissionID: second.id, rewardSettledAt: reviewedAt)
        context.insert(occurrence)
        context.insert(first)
        context.insert(second)
        context.insert(completion)
        occurrence.statusRawValue = TaskOccurrenceStatus.completed.rawValue
        occurrence.completionRecord = completion
        completion.occurrence = occurrence
        try context.save()
        occurrence.xpRewardSnapshot = 99
        occurrence.scheduledAt = now.addingTimeInterval(3600)
        try context.save()
    }
}
