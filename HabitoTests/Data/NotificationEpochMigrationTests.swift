import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("稍后验收世代兼容迁移")
struct NotificationEpochMigrationTests {
    @Test("独立完整或空结构五迁移，不猜旧映射世代、不丢审核奖励或计时", arguments: [false, true])
    func versionFiveMigrationPreservesFacts(empty: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V4MigrationFixture.seed(at: url, empty: empty)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            if empty {
                #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
                #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
            } else {
                try verifyCompleteFacts(context)
            }
        }
    }

    @Test("新增可空世代字段重开保持明确值，旧标识/时间/审核和交易不变", arguments: [false, true])
    func epochMetadataPersistsWithoutChangingAudit(hasEpoch: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V4MigrationFixture.seed(at: url)
        try setSyntheticEpoch(at: url, hasEpoch: hasEpoch)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let link = try #require(context.fetch(FetchDescriptor<NotificationLink>()).first { $0.kind == .snooze })
            #expect(link.submissionIDAtScheduling == (hasEpoch ? V4MigrationFixture.approvedID : nil))
            #expect(
                link.requestIdentifier
                    == NotificationRequestIdentifier(occurrenceID: V0MigrationFixture.completedID, kind: .snooze)
                    .rawValue)
            #expect(link.scheduledAt == (try V0MigrationFixture.instant("2026-09-22T11:38:00Z")))
            #expect(link.createdAt == (try V0MigrationFixture.instant("2026-09-22T11:28:00Z")))
            try verifyAuditAndTiming(context)
        }
        // 这里只验证可空字段结构，不冒充实际稍后服务为已完成任务创建了请求。
    }

    @Test("四版更早旧库新增映射世代都保持 nil，仍无凭空提交或补奖", arguments: [0, 1, 2, 3])
    func earlierStoresDoNotInventEpoch(version: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        switch version {
        case 0: try V0MigrationFixture.seed(at: url)
        case 1: try V1MigrationFixture.seed(at: url)
        case 2: try V2MigrationFixture.seed(at: url)
        default: try V3MigrationFixture.seed(at: url)
        }
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            #expect(
                try context.fetch(FetchDescriptor<NotificationLink>()).allSatisfy { $0.submissionIDAtScheduling == nil }
            )
            #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
            #expect(
                try context.fetchCount(FetchDescriptor<XPTransaction>()) == (version == 3 ? 3 : version == 2 ? 1 : 0))
            #expect(
                try context.fetchCount(FetchDescriptor<CoinTransaction>()) == (version == 3 ? 3 : version == 2 ? 1 : 0))
        }
    }

    private func verifyCompleteFacts(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ReminderRule>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<DayOverride>()) == 1)
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.hasParentPIN && settings.parentPINCredentialKey == "habito.parent-pin")
        let links = try context.fetch(FetchDescriptor<NotificationLink>())
        #expect(links.count == 2 && links.allSatisfy { $0.submissionIDAtScheduling == nil })
        #expect(Set(links.map(\.occurrenceID)) == [V0MigrationFixture.completedID, V0MigrationFixture.pendingID])
        #expect(links.allSatisfy { $0.occurrence?.id == $0.occurrenceID })
        let snooze = try #require(links.first { $0.kind == .snooze })
        #expect(snooze.scheduledAt == (try V0MigrationFixture.instant("2026-09-22T11:38:00Z")))
        #expect(snooze.createdAt == (try V0MigrationFixture.instant("2026-09-22T11:28:00Z")))
        try verifyAuditAndTiming(context)
    }

    private func verifyAuditAndTiming(_ context: ModelContext) throws {
        let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
        let approved = try #require(occurrences.first { $0.id == V0MigrationFixture.completedID })
        let waiting = try #require(occurrences.first { $0.id == V0MigrationFixture.pendingID })
        let paused = try #require(occurrences.first { $0.id == V0MigrationFixture.activeID })
        let history = TaskSubmissionHistory(context: context)
        let rows = try history.records(for: approved.id)
        #expect(rows.map(\.id) == [V4MigrationFixture.returnedID, V4MigrationFixture.approvedID])
        #expect(rows.map(\.reviewState) == [.returned, .approved])
        #expect(rows.first?.xpRewardSnapshot == 11 && rows.last?.xpRewardSnapshot == 13)
        #expect(rows.first?.activeDurationSeconds == 30 && rows.last?.activeDurationSeconds == 40)
        #expect(try history.latest(for: waiting)?.id == V4MigrationFixture.waitingID)
        #expect(try history.latest(for: waiting)?.reviewState == .waiting)
        #expect(waiting.status == .pending && waiting.completionRecord == nil)
        let completed = try #require(approved.completionRecord)
        #expect(completed.id == V0MigrationFixture.orphanID && completed.submissionID == V4MigrationFixture.approvedID)
        #expect(completed.completedAt == (try V0MigrationFixture.instant("2026-09-22T11:29:00Z")))
        #expect(completed.rewardSettledAt == (try V0MigrationFixture.instant("2026-09-23T11:29:00Z")))
        #expect(completed.rewardSettlementVersion == 2 && completed.completionSource == .parentApproval)
        let allCompletions = try context.fetch(FetchDescriptor<CompletionRecord>())
        #expect(allCompletions.count == 2)
        for record in allCompletions { _ = try TaskCompletionAuditValidator(context: context).validate(record) }
        #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 13, coins: 13))
        #expect(
            Set(try context.fetch(FetchDescriptor<XPTransaction>()).map(\.id))
                == Set([31, 33, 35].map { V4MigrationFixture.stableID(UInt8($0)) }))
        #expect(
            Set(try context.fetch(FetchDescriptor<CoinTransaction>()).map(\.id))
                == Set([32, 34, 36].map { V4MigrationFixture.stableID(UInt8($0)) }))
        #expect(paused.status == .inProgress && paused.timerSessions.first?.id == V3MigrationFixture.pausedSessionID)
        #expect(
            paused.timerSessions.first?.state == .paused && paused.timerSessions.first?.accumulatedActiveSeconds == 30)
        #expect(
            approved.timerSessions.first?.accumulatedActiveSeconds == 40
                && approved.timerSessions.first?.state == .ended)
    }

    private func setSyntheticEpoch(at url: URL, hasEpoch: Bool) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let link = try #require(context.fetch(FetchDescriptor<NotificationLink>()).first { $0.kind == .snooze })
        link.submissionIDAtScheduling = hasEpoch ? V4MigrationFixture.approvedID : nil
        try context.save()
    }
}
