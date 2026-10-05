import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("V0 到 V1 兼容字段迁移")
struct HabitoSchemaMigrationTests {
    @Test("旧非版本与版本库迁移后零奖励与未知历史保持，重开不改写", arguments: [true, false])
    func migratedLegacyDefaultsRemainStable(versioned: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V0MigrationFixture.seed(at: url, versioned: versioned)
        try verifyLegacyDefaults(at: url)
        try verifyLegacyDefaults(at: url)
        try verifyLegacyDefaults(at: url)
    }

    @Test("空旧库能迁移为空 V1，不暗中创建奖励或家庭数据", arguments: [true, false])
    func emptyLegacyStoreMigratesWithoutSeeding(versioned: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try createEmptyLegacyStore(at: url, versioned: versioned)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            #expect(try context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
        }
    }

    @Test("新 V1 磁盘库保存显式配置快照，模板修改不改实例")
    func newConfiguredSnapshotsSurviveReopenAndTemplateEdit() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try seedConfiguredNewStore(at: url)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
            let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            let completion = try #require(occurrence.completionRecord)
            #expect(template.category == .challenge && template.xpReward == 99)
            #expect(template.coinReward == 88 && template.activeBonusCoin == 77)
            #expect(occurrence.categorySnapshot == .growth && occurrence.timePeriodSnapshot == .afterSchool)
            #expect(occurrence.verificationTypeSnapshot == .parentApproval)
            #expect(
                occurrence.xpRewardSnapshot == 11 && occurrence.coinRewardSnapshot == 7
                    && occurrence.activeBonusCoinSnapshot == 3)
            #expect(occurrence.plannedAt == (try V0MigrationFixture.instant("2026-09-22T11:00:00Z")))
            #expect(occurrence.scheduledAt == (try V0MigrationFixture.instant("2026-09-22T11:30:00Z")))
            #expect(occurrence.deadlineAt == (try V0MigrationFixture.instant("2026-09-22T12:00:00Z")))
            #expect(template.reminderRule?.plannedTimeOfDayMinutes == 19 * 60)
            #expect(template.reminderRule?.deadlineTimeOfDayMinutes == 20 * 60)
            #expect(completion.completionTiming == .beforeReminder)
            #expect(completion.completedAt == (try V0MigrationFixture.instant("2026-09-22T11:29:00Z")))
            #expect(completion.occurrence?.id == occurrence.id)
        }
    }

    @Test("未知新字段原始值明确返回空，不能伪装成合法兼容默认")
    func malformedNewRawValuesDoNotSilentlyBecomeDefaults() throws {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        let template = TaskTemplate(
            title: "合成损坏", iconName: "book.fill", colorToken: "reading", targetDurationSeconds: 900,
            createdAt: now, updatedAt: now)
        context.insert(template)
        template.categoryRawValue = "not-a-category"
        template.timePeriodRawValue = "not-a-period"
        template.verificationTypeRawValue = "not-a-verification"
        #expect(template.category == nil && template.timePeriod == nil && template.verificationType == nil)
        let record = CompletionRecord(
            occurrenceID: V0MigrationFixture.completedID, completedAt: now, activeDurationSeconds: 0,
            completionSource: .childManual, createdAt: now, updatedAt: now)
        context.insert(record)
        record.completionTimingRawValue = "not-a-timing"
        #expect(record.completionTiming == nil)
    }

    @Test("提交严格早于快照才自主，相等和晚于均非自主", arguments: [-1.0, 0.0, 1.0])
    func completionTimingUsesStrictSubmissionBoundary(offset: TimeInterval) throws {
        let reminder = try V0MigrationFixture.instant("2026-09-22T11:30:00Z")
        let result = CompletionTiming.classify(submittedAt: reminder.addingTimeInterval(offset), reminderAt: reminder)
        #expect(result == (offset < 0 ? .beforeReminder : .afterReminder))
        // 判定接口不接受家长通过或实际送达时间，不能在等待一天后重解释原提交。
    }

    @Test("损坏存储报错，不用删库回退覆盖原文件")
    func invalidStoreIsRejectedWithoutDestructiveFallback() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let original = Data("合成无效存储，不能删掉后伪装成新库".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) { try AppModelContainer.make(storeURL: url) }
        #expect(try Data(contentsOf: url) == original)
    }

    private func createEmptyLegacyStore(at url: URL, versioned: Bool) throws {
        let context = ModelContext(try V0MigrationFixture.container(at: url, versioned: versioned))
        try context.save()
    }

    private func verifyLegacyDefaults(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
        let records = try context.fetch(FetchDescriptor<CompletionRecord>())
        let rules = try context.fetch(FetchDescriptor<ReminderRule>())
        #expect(templates.count == 2 && occurrences.count == 4 && records.count == 2 && rules.count == 1)
        for template in templates {
            #expect(
                template.category == .unassigned && template.timePeriod == .allDay
                    && template.verificationType == .selfConfirm)
            #expect(template.xpReward == 0 && template.coinReward == 0 && template.activeBonusCoin == 0)
        }
        for occurrence in occurrences {
            #expect(occurrence.categorySnapshot == .unassigned && occurrence.timePeriodSnapshot == .allDay)
            #expect(occurrence.verificationTypeSnapshot == .selfConfirm)
            #expect(
                occurrence.xpRewardSnapshot == 0 && occurrence.coinRewardSnapshot == 0
                    && occurrence.activeBonusCoinSnapshot == 0)
            #expect(occurrence.plannedAt == nil && occurrence.deadlineAt == nil)
        }
        #expect(records.allSatisfy { $0.completionTiming == .unknown })
        #expect(rules.allSatisfy { $0.plannedTimeOfDayMinutes == nil && $0.deadlineTimeOfDayMinutes == nil })
        let completed = try #require(occurrences.first { $0.id == V0MigrationFixture.completedID })
        #expect(completed.scheduledAt == (try V0MigrationFixture.instant("2026-09-21T11:30:00Z")))
        #expect(completed.completionRecord?.completedAt == (try V0MigrationFixture.instant("2026-09-21T11:45:00Z")))
        #expect(try context.fetchCount(FetchDescriptor<TimerSession>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<NotificationLink>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<DayOverride>()) == 2)
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.hasParentPIN && settings.parentPINCredentialKey == AppSettings.parentPINKeychainAccount)
        #expect(settings.schemaVersion == 1)  // 原业务字段保持；实际版本以 SwiftData 元数据为准。
    }

    private func seedConfiguredNewStore(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T11:29:00Z")
        // 下列数值只是证明字段独立性的显式合成输入，不是未经确认的产品默认。
        let template = TaskTemplate(
            id: V0MigrationFixture.templateID, title: "合成 V1", iconName: "book.fill", colorToken: "reading",
            targetDurationSeconds: 900, createdAt: now, updatedAt: now,
            category: .growth, timePeriod: .afterSchool, verificationType: .parentApproval,
            xpReward: 11, coinReward: 7, activeBonusCoin: 3)
        let rule = ReminderRule(
            id: V0MigrationFixture.ruleID, taskTemplateID: template.id,
            recurrence: .once(on: try V0MigrationFixture.date("2026-09-22")), timeOfDayMinutes: 19 * 60 + 30,
            plannedTimeOfDayMinutes: 19 * 60, deadlineTimeOfDayMinutes: 20 * 60)
        let scheduledAt = try V0MigrationFixture.instant("2026-09-22T11:30:00Z")
        let occurrence = TaskOccurrence(
            id: V0MigrationFixture.completedID, templateID: template.id,
            date: try V0MigrationFixture.date("2026-09-22"),
            scheduledAt: scheduledAt, titleSnapshot: template.title, iconSnapshot: template.iconName,
            colorSnapshot: template.colorToken, targetDurationSnapshot: 900, status: .completed, sourceRevision: 1,
            createdAt: now, updatedAt: now, categorySnapshot: .growth, timePeriodSnapshot: .afterSchool,
            verificationTypeSnapshot: .parentApproval, xpRewardSnapshot: 11, coinRewardSnapshot: 7,
            activeBonusCoinSnapshot: 3,
            plannedAt: try V0MigrationFixture.instant("2026-09-22T11:00:00Z"),
            deadlineAt: try V0MigrationFixture.instant("2026-09-22T12:00:00Z"))
        let completion = CompletionRecord(
            id: V0MigrationFixture.orphanID, occurrenceID: occurrence.id, completedAt: now,
            activeDurationSeconds: 900, completionSource: .childManual, createdAt: now, updatedAt: now,
            completionTiming: .classify(submittedAt: now, reminderAt: scheduledAt))
        context.insert(template)
        context.insert(rule)
        context.insert(occurrence)
        context.insert(completion)
        template.reminderRule = rule
        occurrence.template = template
        occurrence.completionRecord = completion
        completion.occurrence = occurrence
        try context.save()
        template.categoryRawValue = TaskCategory.challenge.rawValue
        template.xpReward = 99
        template.coinReward = 88
        template.activeBonusCoin = 77
        try context.save()
    }
}
