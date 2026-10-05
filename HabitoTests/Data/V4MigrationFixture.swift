import Foundation
import SwiftData
@testable import Habito

/// 独立结构 5.0.0 建库，覆盖提交/审核/奖励与旧稍后槽位，不使用当前模型冒充旧库。
@MainActor
enum V4MigrationFixture {
    static let returnedID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20))
    static let approvedID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21))
    static let waitingID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 22))
    static let historicalCompletionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 30))

    static func seed(at url: URL, empty: Bool = false) throws {
        let schema = Schema(versionedSchema: HabitoSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
        context.autosaveEnabled = false
        if empty { try context.save(); return }
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let reviewedAt = now.addingTimeInterval(86400)
        let reminder = now.addingTimeInterval(60)
        let template = HabitoSchemaV4.TaskTemplate(
            id: V0MigrationFixture.templateID,
            title: "合成结构五", iconName: "book.fill", colorToken: "reading", targetDurationSeconds: 900,
            createdAt: now, updatedAt: now, category: .growth, timePeriod: .afterSchool,
            verificationType: .parentApproval, xpReward: 13, coinReward: 9, activeBonusCoin: 4)
        let rule = HabitoSchemaV4.ReminderRule(
            id: V0MigrationFixture.ruleID, taskTemplateID: template.id,
            recurrence: .once(on: try V0MigrationFixture.date("2026-09-22")), timeOfDayMinutes: 1170)
        let approvedOccurrence = makeOccurrence(
            id: V0MigrationFixture.completedID, templateID: template.id,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: reminder, status: .completed, at: now)
        let waitingOccurrence = makeOccurrence(
            id: V0MigrationFixture.pendingID, templateID: template.id,
            date: try V0MigrationFixture.date("2026-09-23"), scheduledAt: reminder.addingTimeInterval(86400),
            status: .pending, at: now)
        let activeOccurrence = makeOccurrence(
            id: V0MigrationFixture.activeID, templateID: template.id,
            date: try V0MigrationFixture.date("2026-09-24"), scheduledAt: reminder.addingTimeInterval(172800),
            status: .inProgress, at: now)
        let returned = HabitoSchemaV4.TaskSubmission(
            id: returnedID, occurrenceID: approvedOccurrence.id, sequenceNumber: 1,
            snapshot: try CompletionRewardSnapshot(
                submittedAt: now.addingTimeInterval(-120), reminderAt: reminder,
                xp: 11, baseCoins: 7, autonomyBonusCoins: 3), activeDurationSeconds: 30,
            reviewState: .returned, reviewedAt: now.addingTimeInterval(-60))
        let approved = HabitoSchemaV4.TaskSubmission(
            id: approvedID, occurrenceID: approvedOccurrence.id, sequenceNumber: 2,
            snapshot: try CompletionRewardSnapshot(
                submittedAt: now, reminderAt: reminder, xp: 13, baseCoins: 9, autonomyBonusCoins: 4),
            activeDurationSeconds: 40, reviewState: .approved, reviewedAt: reviewedAt,
            reviewedCompletionID: V0MigrationFixture.orphanID)
        let waiting = HabitoSchemaV4.TaskSubmission(
            id: waitingID, occurrenceID: waitingOccurrence.id, sequenceNumber: 1,
            snapshot: try CompletionRewardSnapshot(
                submittedAt: reviewedAt, reminderAt: reminder.addingTimeInterval(86400),
                xp: 13, baseCoins: 9, autonomyBonusCoins: 4), activeDurationSeconds: 0)
        let completion = HabitoSchemaV4.CompletionRecord(
            id: V0MigrationFixture.orphanID, occurrenceID: approvedOccurrence.id,
            completedAt: now, activeDurationSeconds: 40, completionSource: .parentApproval, createdAt: reviewedAt,
            updatedAt: reviewedAt,
            completionTiming: .beforeReminder, reminderAtSnapshot: reminder, xpRewardSnapshot: 13,
            coinRewardSnapshot: 9,
            activeBonusCoinSnapshot: 4, settledCoinSnapshot: 13, rewardSettlementVersion: 2,
            submissionID: approvedID, rewardSettledAt: reviewedAt)
        let earlier = now.addingTimeInterval(-180)
        let revokedAt = earlier.addingTimeInterval(1)
        let historical = HabitoSchemaV4.CompletionRecord(
            id: historicalCompletionID, occurrenceID: approvedOccurrence.id,
            completedAt: earlier, activeDurationSeconds: 20, completionSource: .childManual, createdAt: earlier,
            updatedAt: revokedAt,
            completionTiming: .beforeReminder, reminderAtSnapshot: reminder, xpRewardSnapshot: 3, coinRewardSnapshot: 2,
            settledCoinSnapshot: 2, rewardSettlementVersion: 1, revokedAt: revokedAt)
        let ended = HabitoSchemaV4.TimerSession(
            id: V0MigrationFixture.ruleID, occurrenceID: approvedOccurrence.id, state: .ended,
            startedAt: now.addingTimeInterval(-60), lastResumedAt: now.addingTimeInterval(-60),
            accumulatedActiveSeconds: 40, endedAt: now)
        let paused = HabitoSchemaV4.TimerSession(
            id: V3MigrationFixture.pausedSessionID, occurrenceID: activeOccurrence.id, state: .paused,
            startedAt: earlier, lastResumedAt: earlier, accumulatedActiveSeconds: 30)
        let snooze = HabitoSchemaV4.NotificationLink(
            requestIdentifier: NotificationRequestIdentifier(occurrenceID: approvedOccurrence.id, kind: .snooze)
                .rawValue,
            occurrenceID: approvedOccurrence.id, kind: .snooze, scheduledAt: now.addingTimeInterval(540),
            createdAt: now.addingTimeInterval(-60))
        let primary = HabitoSchemaV4.NotificationLink(
            requestIdentifier: NotificationRequestIdentifier(occurrenceID: waitingOccurrence.id, kind: .primary)
                .rawValue,
            occurrenceID: waitingOccurrence.id, kind: .primary, scheduledAt: reminder.addingTimeInterval(86400),
            createdAt: now)
        context.insert(template)
        context.insert(rule)
        [approvedOccurrence, waitingOccurrence, activeOccurrence].forEach(context.insert)
        [returned, approved, waiting].forEach(context.insert)
        [completion, historical].forEach(context.insert)
        [ended, paused].forEach(context.insert)
        [snooze, primary].forEach(context.insert)
        context.insert(
            HabitoSchemaV4.DayOverride(
                date: try V0MigrationFixture.date("2026-09-25"), dayType: .holiday, updatedAt: now))
        context.insert(HabitoSchemaV4.AppSettings(hasParentPIN: true, lastNotificationSchedulingAt: now))
        insertReward(context, sourceID: completion.id, xp: 13, coins: 13, at: reviewedAt, index: 31)
        insertReward(context, sourceID: historical.id, xp: 3, coins: 2, at: earlier, index: 33)
        context.insert(
            HabitoSchemaV4.XPTransaction(
                id: stableID(35), businessKey: RewardLedgerKey.xpReversal(historical.id),
                sourceID: historical.id, kind: .reversal, amount: -3,
                reversalOfBusinessKey: RewardLedgerKey.xpReward(historical.id), createdAt: revokedAt))
        context.insert(
            HabitoSchemaV4.CoinTransaction(
                id: stableID(36), businessKey: RewardLedgerKey.coinReversal(historical.id),
                sourceID: historical.id, kind: .reversal, amount: -2,
                reversalOfBusinessKey: RewardLedgerKey.coinReward(historical.id), createdAt: revokedAt))
        template.reminderRule = rule
        rule.taskTemplate = template
        [approvedOccurrence, waitingOccurrence, activeOccurrence].forEach { $0.template = template }
        approvedOccurrence.completionRecord = completion
        completion.occurrence = approvedOccurrence
        ended.occurrence = approvedOccurrence
        paused.occurrence = activeOccurrence
        snooze.occurrence = approvedOccurrence
        primary.occurrence = waitingOccurrence
        try context.save()
    }

    static func stableID(_ index: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, index))
    }

    private static func makeOccurrence(
        id: UUID, templateID: UUID, date: LocalDate, scheduledAt: Date,
        status: TaskOccurrenceStatus, at now: Date
    ) -> HabitoSchemaV4.TaskOccurrence {
        HabitoSchemaV4.TaskOccurrence(
            id: id, templateID: templateID, date: date, scheduledAt: scheduledAt,
            titleSnapshot: "合成结构五", iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            status: status, sourceRevision: 1, createdAt: now, updatedAt: now, categorySnapshot: .growth,
            timePeriodSnapshot: .afterSchool, verificationTypeSnapshot: .parentApproval,
            xpRewardSnapshot: 13, coinRewardSnapshot: 9, activeBonusCoinSnapshot: 4)
    }

    private static func insertReward(
        _ context: ModelContext, sourceID: UUID, xp: Int, coins: Int, at now: Date, index: UInt8
    ) {
        context.insert(
            HabitoSchemaV4.XPTransaction(
                id: stableID(index), businessKey: RewardLedgerKey.xpReward(sourceID),
                sourceID: sourceID, kind: .reward, amount: xp, createdAt: now))
        context.insert(
            HabitoSchemaV4.CoinTransaction(
                id: stableID(index + 1), businessKey: RewardLedgerKey.coinReward(sourceID),
                sourceID: sourceID, kind: .reward, amount: coins, createdAt: now))
    }
}
