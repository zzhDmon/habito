import Foundation
import SwiftData
@testable import Habito

/// 用独立冻结的 3.0.0 结构建库，不能用当前容器冒充上一版。
@MainActor
enum V2MigrationFixture {
    static func seed(at url: URL) throws {
        let schema = Schema(versionedSchema: HabitoSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let scheduledAt = try V0MigrationFixture.instant("2026-09-22T11:30:00Z")
        // 显式合成数值只验证迁移，不是产品默认；迁移不能把旧快照变成发奖指令。
        let template = HabitoSchemaV2.TaskTemplate(
            id: V0MigrationFixture.templateID, title: "合成上一版", iconName: "book.fill", colorToken: "reading",
            targetDurationSeconds: 900, createdAt: now, updatedAt: now,
            category: .growth, timePeriod: .afterSchool, verificationType: .parentApproval,
            xpReward: 11, coinReward: 7, activeBonusCoin: 3)
        let rule = HabitoSchemaV2.ReminderRule(
            id: V0MigrationFixture.ruleID, taskTemplateID: template.id,
            recurrence: .once(on: try V0MigrationFixture.date("2026-09-22")), timeOfDayMinutes: 1170,
            plannedTimeOfDayMinutes: 1140, deadlineTimeOfDayMinutes: 1200)
        let occurrence = HabitoSchemaV2.TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: template.id,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: scheduledAt,
            titleSnapshot: template.title, iconSnapshot: template.iconName, colorSnapshot: template.colorToken,
            targetDurationSnapshot: 900, status: .completed, sourceRevision: 1, createdAt: now, updatedAt: now,
            categorySnapshot: .growth, timePeriodSnapshot: .afterSchool, verificationTypeSnapshot: .parentApproval,
            xpRewardSnapshot: 11, coinRewardSnapshot: 7, activeBonusCoinSnapshot: 3,
            plannedAt: try V0MigrationFixture.instant("2026-09-22T11:00:00Z"),
            deadlineAt: try V0MigrationFixture.instant("2026-09-22T12:00:00Z"))
        let completion = HabitoSchemaV2.CompletionRecord(
            id: V0MigrationFixture.orphanID, occurrenceID: occurrence.id, completedAt: now,
            activeDurationSeconds: 900, completionSource: .childManual, createdAt: now, updatedAt: now,
            completionTiming: .beforeReminder)
        let settings = HabitoSchemaV2.AppSettings(hasParentPIN: true)
        context.insert(template)
        context.insert(rule)
        context.insert(occurrence)
        context.insert(completion)
        context.insert(settings)
        context.insert(
            HabitoSchemaV2.XPTransaction(
                id: V0MigrationFixture.activeID,
                businessKey: RewardLedgerKey.xpReward(completion.id),
                sourceID: completion.id, kind: .reward, amount: 11, createdAt: now))
        context.insert(
            HabitoSchemaV2.CoinTransaction(
                id: V0MigrationFixture.pendingID,
                businessKey: RewardLedgerKey.coinReward(completion.id),
                sourceID: completion.id, kind: .reward, amount: 10, createdAt: now))
        // iPadOS 17 要求先注册所有模型再建立关系；不跨容器传活跃模型对象。
        template.reminderRule = rule
        occurrence.template = template
        occurrence.completionRecord = completion
        completion.occurrence = occurrence
        try context.save()
    }
}
