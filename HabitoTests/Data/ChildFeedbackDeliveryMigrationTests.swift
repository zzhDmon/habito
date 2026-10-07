import Foundation
import SwiftData
import Testing
@testable import Habito

/// 只验证独立历史结构与新投递字段，不把合成字段写入冒充正式审核/投递用例。
@MainActor
@Suite("儿童审核收据投递兼容迁移")
struct ChildFeedbackDeliveryMigrationTests {
    @Test("冻结六与当前七保持十一模型，仅完成记录增加两项展示元数据")
    func schemaAddsOnlyDeliveryMetadata() throws {
        let old = Schema(versionedSchema: HabitoSchemaV5.self)
        let current = AppModelContainer.schema
        #expect(HabitoSchemaV5.versionIdentifier == Schema.Version(6, 0, 0))
        #expect(HabitoSchemaV6.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(old.entities.count == 11 && current.entities.count == 11)
        #expect(Set(old.entities.map(\.name)) == Set(current.entities.map(\.name)))
        for entity in old.entities {
            let counterpart = try #require(current.entities.first { $0.name == entity.name })
            let added: Set<String> =
                entity.name == "CompletionRecord"
                ? ["childFeedbackDeliveryVersion", "childFeedbackAcknowledgedAt"] : []
            #expect(Set(counterpart.properties.map(\.name)) == Set(entity.properties.map(\.name)).union(added))
        }
        for (frozen, active) in zip(HabitoSchemaV5.models, HabitoSchemaV6.models) {
            #expect(ObjectIdentifier(frozen) != ObjectIdentifier(active))
        }
    }

    @Test("独立六版完整或空库升级重开不丢事实，不自动标旧记录可投递", arguments: [false, true])
    func versionSixMigrationPreservesFacts(empty: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V5MigrationFixture.seed(at: url, empty: empty)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            try expectFeedbackDisabled(context)
            if empty {
                #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
                #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
            } else {
                try expectMigratedFacts(context)
            }
            #expect(!context.hasChanges)
        }
    }

    @Test("更早五版升级也不补弹历史或补写奖励，固定交易和通知世代保持", arguments: Array(0..<5))
    func earlierStoresKeepFeedbackDisabled(version: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        switch version {
        case 0: try V0MigrationFixture.seed(at: url)
        case 1: try V1MigrationFixture.seed(at: url)
        case 2: try V2MigrationFixture.seed(at: url)
        case 3: try V3MigrationFixture.seed(at: url)
        default: try V4MigrationFixture.seed(at: url)
        }
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            try expectFeedbackDisabled(context)
            let count = version >= 3 ? 3 : version == 2 ? 1 : 0
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == count)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == count)
            #expect(
                try context.fetch(FetchDescriptor<NotificationLink>()).allSatisfy { $0.submissionIDAtScheduling == nil }
            )
            #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == (version == 4 ? 3 : 0))
            #expect(!context.hasChanges)
        }
    }

    @Test("合成待确认或已确认及零奖励展示元数据重开保持，不增加交易", arguments: [false, true], [false, true])
    func explicitMetadataSurvivesReopen(zeroReward: Bool, acknowledged: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let at = try V0MigrationFixture.instant("2026-09-23T11:29:00Z")
        try seedExplicitMetadata(at: url, settledAt: at, zeroReward: zeroReward, acknowledged: acknowledged)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let record = try #require(context.fetch(FetchDescriptor<CompletionRecord>()).first)
            #expect(record.id == V0MigrationFixture.orphanID && record.childFeedbackDeliveryVersion == 1)
            #expect(record.childFeedbackAcknowledgedAt == (acknowledged ? at.addingTimeInterval(60) : nil))
            #expect(record.completedAt == at.addingTimeInterval(-86400) && record.rewardSettledAt == at)
            #expect(record.rewardSettlementVersion == 2 && record.submissionID == V5MigrationFixture.approvedID)
            _ = try TaskCompletionAuditValidator(context: context).validate(record)
            #expect(
                try RewardLedgerService(context: context).balance()
                    == RewardBalance(effectiveXP: zeroReward ? 0 : 13, coins: zeroReward ? 0 : 13))
            #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 1)
            #expect(!context.hasChanges)
        }
    }

    private func expectFeedbackDisabled(_ context: ModelContext) throws {
        #expect(
            try context.fetch(FetchDescriptor<CompletionRecord>()).allSatisfy {
                $0.childFeedbackDeliveryVersion == 0 && $0.childFeedbackAcknowledgedAt == nil
            })
    }

    private func expectMigratedFacts(_ context: ModelContext) throws {
        let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
        let rule = try #require(template.reminderRule)
        #expect(template.id == V0MigrationFixture.templateID && template.title == "合成结构六")
        #expect(
            template.category == .growth && template.timePeriod == .afterSchool
                && template.verificationType == .parentApproval)
        #expect(template.xpReward == 13 && template.coinReward == 9 && template.activeBonusCoin == 4)
        #expect(rule.id == V0MigrationFixture.ruleID && rule.taskTemplate?.id == template.id)
        #expect(
            rule.timeOfDayMinutes == 1170 && rule.plannedTimeOfDayMinutes == 495 && rule.deadlineTimeOfDayMinutes == 560
        )
        let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
        #expect(
            Set(occurrences.map(\.id)) == [
                V0MigrationFixture.completedID, V0MigrationFixture.pendingID, V0MigrationFixture.activeID,
            ])
        #expect(
            occurrences.allSatisfy {
                $0.template?.id == template.id && $0.plannedAt == $0.scheduledAt.addingTimeInterval(-3600)
                    && $0.deadlineAt == $0.scheduledAt.addingTimeInterval(1800)
            })
        let completed = try #require(occurrences.first { $0.id == V0MigrationFixture.completedID })
        let record = try #require(completed.completionRecord)
        #expect(record.id == V0MigrationFixture.orphanID && record.submissionID == V5MigrationFixture.approvedID)
        #expect(
            record.rewardSettlementVersion == 2 && record.completionSource == .parentApproval
                && record.completionTiming == .beforeReminder)
        #expect(record.completedAt == (try V0MigrationFixture.instant("2026-09-22T11:29:00Z")))
        #expect(record.rewardSettledAt == (try V0MigrationFixture.instant("2026-09-23T11:29:00Z")))
        let history = TaskSubmissionHistory(context: context)
        #expect(
            try history.records(for: completed.id).map(\.id) == [
                V5MigrationFixture.returnedID, V5MigrationFixture.approvedID,
            ])
        let waiting = try #require(occurrences.first { $0.id == V0MigrationFixture.pendingID })
        #expect(try history.latest(for: waiting)?.id == V5MigrationFixture.waitingID)
        #expect(try history.latest(for: waiting)?.reviewState == .waiting && waiting.completionRecord == nil)
        let allCompletions = try context.fetch(FetchDescriptor<CompletionRecord>())
        #expect(
            Set(allCompletions.map(\.id)) == [V0MigrationFixture.orphanID, V5MigrationFixture.historicalCompletionID])
        for row in allCompletions { _ = try TaskCompletionAuditValidator(context: context).validate(row) }
        #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 13, coins: 13))
        #expect(
            Set(try context.fetch(FetchDescriptor<XPTransaction>()).map(\.id))
                == Set([31, 33, 35].map { V5MigrationFixture.stableID(UInt8($0)) }))
        #expect(
            Set(try context.fetch(FetchDescriptor<CoinTransaction>()).map(\.id))
                == Set([32, 34, 36].map { V5MigrationFixture.stableID(UInt8($0)) }))
        let paused = try #require(occurrences.first { $0.id == V0MigrationFixture.activeID })
        #expect(paused.status == .inProgress && paused.timerSessions.first?.id == V3MigrationFixture.pausedSessionID)
        #expect(
            paused.timerSessions.first?.state == .paused && paused.timerSessions.first?.accumulatedActiveSeconds == 30)
        #expect(
            completed.timerSessions.first?.state == .ended
                && completed.timerSessions.first?.accumulatedActiveSeconds == 40)
        let links = try context.fetch(FetchDescriptor<NotificationLink>())
        #expect(links.count == 2 && links.allSatisfy { $0.occurrence?.id == $0.occurrenceID })
        let snooze = try #require(links.first { $0.kind == .snooze })
        #expect(snooze.submissionIDAtScheduling == V5MigrationFixture.approvedID)
        #expect(snooze.scheduledAt == (try V0MigrationFixture.instant("2026-09-22T11:38:00Z")))
        #expect(links.first { $0.kind == .primary }?.submissionIDAtScheduling == nil)
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.hasParentPIN && settings.parentPINCredentialKey == "habito.parent-pin")
        #expect(try context.fetchCount(FetchDescriptor<DayOverride>()) == 1)
    }

    /// 直接构造合法审计/账本图，只测试字段重开；B0 不把正式审核入口提前改成可投递。
    private func seedExplicitMetadata(at url: URL, settledAt: Date, zeroReward: Bool, acknowledged: Bool) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let submittedAt = settledAt.addingTimeInterval(-86400)
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: submittedAt, reminderAt: submittedAt.addingTimeInterval(60), xp: zeroReward ? 0 : 13,
            baseCoins: zeroReward ? 0 : 9, autonomyBonusCoins: zeroReward ? 0 : 4)
        let occurrence = TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: V0MigrationFixture.templateID,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: snapshot.reminderAt, titleSnapshot: "合成投递元数据",
            iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900, status: .completed,
            sourceRevision: 1, createdAt: submittedAt, updatedAt: settledAt, verificationTypeSnapshot: .parentApproval,
            xpRewardSnapshot: snapshot.xp, coinRewardSnapshot: snapshot.baseCoins,
            activeBonusCoinSnapshot: snapshot.autonomyBonusCoins)
        let submission = TaskSubmission(
            id: V5MigrationFixture.approvedID, occurrenceID: occurrence.id, sequenceNumber: 1, snapshot: snapshot,
            activeDurationSeconds: 40, reviewState: .approved, reviewedAt: settledAt,
            reviewedCompletionID: V0MigrationFixture.orphanID)
        let record = CompletionRecord(
            id: V0MigrationFixture.orphanID, occurrenceID: occurrence.id, completedAt: submittedAt,
            activeDurationSeconds: 40, completionSource: .parentApproval, createdAt: settledAt, updatedAt: settledAt,
            completionTiming: snapshot.timing, reminderAtSnapshot: snapshot.reminderAt, xpRewardSnapshot: snapshot.xp,
            coinRewardSnapshot: snapshot.baseCoins, activeBonusCoinSnapshot: snapshot.autonomyBonusCoins,
            settledCoinSnapshot: snapshot.settledCoins, rewardSettlementVersion: 2, submissionID: submission.id,
            rewardSettledAt: settledAt, childFeedbackDeliveryVersion: 1,
            childFeedbackAcknowledgedAt: acknowledged ? settledAt.addingTimeInterval(60) : nil)
        context.insert(occurrence)
        context.insert(submission)
        context.insert(record)
        context.insert(
            XPTransaction(
                id: V5MigrationFixture.stableID(31), businessKey: RewardLedgerKey.xpReward(record.id),
                sourceID: record.id, kind: .reward, amount: snapshot.xp, createdAt: settledAt))
        context.insert(
            CoinTransaction(
                id: V5MigrationFixture.stableID(32), businessKey: RewardLedgerKey.coinReward(record.id),
                sourceID: record.id, kind: .reward, amount: snapshot.settledCoins, createdAt: settledAt))
        occurrence.completionRecord = record
        record.occurrence = occurrence
        try context.save()
    }
}
