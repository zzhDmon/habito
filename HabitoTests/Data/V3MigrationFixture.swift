import Foundation
import SwiftData
@testable import Habito

/// 直接使用独立结构 4.0.0 建库，覆盖已结算/已撤销和暂停计时，不用当前 schema 冒充旧库。
@MainActor
enum V3MigrationFixture {
    static let pausedSessionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15))
    static func seed(at url: URL) throws {
        let schema = Schema(versionedSchema: HabitoSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let reminder = now.addingTimeInterval(60)
        let earlier = now.addingTimeInterval(-60)
        let revokedAt = earlier.addingTimeInterval(1)
        let template = HabitoSchemaV3.TaskTemplate(
            id: V0MigrationFixture.templateID, title: "合成结构四", iconName: "book.fill", colorToken: "reading",
            targetDurationSeconds: 900, createdAt: now, updatedAt: now,
            category: .growth, timePeriod: .afterSchool, xpReward: 11, coinReward: 7, activeBonusCoin: 3)
        let rule = HabitoSchemaV3.ReminderRule(
            id: V0MigrationFixture.ruleID, taskTemplateID: template.id,
            recurrence: .once(on: try V0MigrationFixture.date("2026-09-22")), timeOfDayMinutes: 1170)
        let occurrence = HabitoSchemaV3.TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: template.id,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: reminder,
            titleSnapshot: template.title, iconSnapshot: template.iconName, colorSnapshot: template.colorToken,
            targetDurationSnapshot: 900, status: .completed, sourceRevision: 1, createdAt: now, updatedAt: now,
            xpRewardSnapshot: 11, coinRewardSnapshot: 7, activeBonusCoinSnapshot: 3)
        let pending = HabitoSchemaV3.TaskOccurrence(
            id: V0MigrationFixture.pendingID, templateID: template.id,
            date: try V0MigrationFixture.date("2026-09-23"), scheduledAt: reminder.addingTimeInterval(86400),
            titleSnapshot: "暂停计时保持", iconSnapshot: "book.fill", colorSnapshot: "reading",
            targetDurationSnapshot: 900, status: .inProgress, sourceRevision: 1, createdAt: now, updatedAt: now)
        let session = HabitoSchemaV3.TimerSession(
            id: pausedSessionID, occurrenceID: pending.id, state: .paused,
            startedAt: earlier, lastResumedAt: earlier, accumulatedActiveSeconds: 30)
        let current = HabitoSchemaV3.CompletionRecord(
            id: V0MigrationFixture.orphanID, occurrenceID: occurrence.id, completedAt: now,
            activeDurationSeconds: 900, completionSource: .childManual, createdAt: now, updatedAt: now,
            completionTiming: .beforeReminder, reminderAtSnapshot: reminder,
            xpRewardSnapshot: 11, coinRewardSnapshot: 7, activeBonusCoinSnapshot: 3,
            settledCoinSnapshot: 10, rewardSettlementVersion: 1)
        let historical = HabitoSchemaV3.CompletionRecord(
            id: V0MigrationFixture.activeID, occurrenceID: occurrence.id, completedAt: earlier,
            activeDurationSeconds: 600, completionSource: .childManual, createdAt: earlier, updatedAt: revokedAt,
            completionTiming: .beforeReminder, reminderAtSnapshot: reminder,
            xpRewardSnapshot: 3, coinRewardSnapshot: 2, settledCoinSnapshot: 2,
            rewardSettlementVersion: 1, revokedAt: revokedAt)
        context.insert(template)
        context.insert(rule)
        context.insert(occurrence)
        context.insert(pending)
        context.insert(session)
        context.insert(current)
        context.insert(historical)
        context.insert(HabitoSchemaV3.AppSettings(hasParentPIN: true, lastNotificationSchedulingAt: now))
        insertReward(context, sourceID: current.id, xp: 11, coins: 10, at: now)
        insertReward(context, sourceID: historical.id, xp: 3, coins: 2, at: earlier)
        context.insert(
            HabitoSchemaV3.XPTransaction(
                id: V0MigrationFixture.completedID,
                businessKey: RewardLedgerKey.xpReversal(historical.id), sourceID: historical.id, kind: .reversal,
                amount: -3, reversalOfBusinessKey: RewardLedgerKey.xpReward(historical.id), createdAt: revokedAt))
        context.insert(
            HabitoSchemaV3.CoinTransaction(
                id: V0MigrationFixture.activeID,
                businessKey: RewardLedgerKey.coinReversal(historical.id), sourceID: historical.id, kind: .reversal,
                amount: -2, reversalOfBusinessKey: RewardLedgerKey.coinReward(historical.id), createdAt: revokedAt))
        // 先入同上下文再连关系；撤销事实故意不连当前单值关系，但外键完整保留。
        template.reminderRule = rule
        occurrence.template = template
        pending.template = template
        occurrence.completionRecord = current
        current.occurrence = occurrence
        session.occurrence = pending
        try context.save()
    }

    private static func insertReward(_ context: ModelContext, sourceID: UUID, xp: Int, coins: Int, at now: Date) {
        context.insert(
            HabitoSchemaV3.XPTransaction(
                id: sourceID == V0MigrationFixture.orphanID
                    ? V0MigrationFixture.activeID : V0MigrationFixture.pendingID,
                businessKey: RewardLedgerKey.xpReward(sourceID), sourceID: sourceID, kind: .reward, amount: xp,
                createdAt: now))
        context.insert(
            HabitoSchemaV3.CoinTransaction(
                id: sourceID == V0MigrationFixture.orphanID
                    ? V0MigrationFixture.orphanID : V0MigrationFixture.completedID,
                businessKey: RewardLedgerKey.coinReward(sourceID), sourceID: sourceID, kind: .reward, amount: coins,
                createdAt: now))
    }
}
