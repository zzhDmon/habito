import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("冻结 V0 schema 与合成旧磁盘库")
struct HabitoSchemaV0Tests {
    @Test("独立历史 schema 仍只有八模型，不跟随当前类型变更")
    func frozenSchemaKeepsOriginalModelContract() {
        let schema = Schema(HabitoSchemaV0.models)
        let expected: [String: Set<String>] = [
            "TaskTemplate": [
                "id", "title", "iconName", "colorToken", "targetDurationSeconds", "isEnabled", "revision",
                "createdAt", "updatedAt", "archivedAt", "reminderRule", "occurrences",
            ],
            "ReminderRule": [
                "id", "taskTemplateID", "scheduleTypeRawValue", "timeOfDayMinutes", "weekdayMask",
                "oneOffDateKey", "startDateKey", "endDateKey", "isEnabled", "taskTemplate",
            ],
            "TaskOccurrence": [
                "id", "uniquenessKey", "templateID", "dateKey", "scheduledAt", "titleSnapshot",
                "iconSnapshot", "colorSnapshot", "targetDurationSnapshot", "statusRawValue",
                "sourceRevision", "isDetachedOverride", "createdAt", "updatedAt", "template",
                "completionRecord", "timerSessions", "notificationLinks",
            ],
            "CompletionRecord": [
                "id", "occurrenceID", "completedAt", "activeDurationSeconds", "completionSourceRawValue",
                "createdAt", "updatedAt", "occurrence",
            ],
            "TimerSession": [
                "id", "occurrenceID", "stateRawValue", "startedAt", "lastResumedAt",
                "accumulatedActiveSeconds", "endedAt", "occurrence",
            ],
            "DayOverride": ["id", "dateKey", "dayTypeRawValue", "note", "updatedAt"],
            "NotificationLink": [
                "requestIdentifier", "occurrenceID", "kindRawValue", "scheduledAt", "createdAt", "occurrence",
            ],
            "AppSettings": [
                "singletonKey", "isOnboardingCompleted", "parentPINCredentialKey", "lastInstanceGenerationAt",
                "lastNotificationSchedulingAt", "schedulingHorizonDateKey", "lastNotificationAuthorizationRawValue",
                "schemaVersion",
            ],
        ]
        #expect(schema.entities.count == 8)
        #expect(Set(schema.entities.map(\.name)) == Set(expected.keys))
        for entity in schema.entities { #expect(Set(entity.properties.map(\.name)) == expected[entity.name]) }
        #expect(ObjectIdentifier(HabitoSchemaV0.TaskTemplate.self) != ObjectIdentifier(TaskTemplate.self))
        #expect(ObjectIdentifier(HabitoSchemaV0.TaskOccurrence.self) != ObjectIdentifier(TaskOccurrence.self))
    }

    @Test("冻结旧库重开保留固定字段关系计时和 PIN 引用", arguments: [TimerSessionState.running, .paused], [true, false])
    func frozenStoreSurvivesReopen(timerState: TimerSessionState, versioned: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V0MigrationFixture.seed(at: url, timerState: timerState, versioned: versioned)
        try verifyFrozenStore(at: url, timerState: timerState, versioned: versioned)
        try verifyFrozenStore(at: url, timerState: timerState, versioned: versioned)
    }

    @Test("当前 V0 可读取独立冻结模型生成的磁盘库且不丢对象", arguments: [TimerSessionState.running, .paused], [true, false])
    func currentV0ReadsFrozenStore(timerState: TimerSessionState, versioned: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V0MigrationFixture.seed(at: url, timerState: timerState, versioned: versioned)
        try verifyCurrentStore(at: url, timerState: timerState)
        try verifyCurrentStore(at: url, timerState: timerState)
    }

    @Test("原非版本 App schema 写入的数据库能由冻结模型读取")
    func frozenSchemaReadsOriginalUnversionedStore() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try seedOriginalAppStore(at: url)
        let context = ModelContext(try V0MigrationFixture.container(at: url))
        let template = try #require(context.fetch(FetchDescriptor<HabitoSchemaV0.TaskTemplate>()).first)
        #expect(template.id == V0MigrationFixture.templateID)
        #expect(template.title == "合成原版模板")
        #expect(template.createdAt == (try V0MigrationFixture.instant("2026-09-20T01:00:00Z")))
        #expect(template.reminderRule?.taskTemplateID == template.id)
        #expect(template.reminderRule?.taskTemplate?.id == template.id)
        #expect(template.reminderRule?.oneOffDateKey == "2026-09-21")
    }

    private func seedOriginalAppStore(at url: URL) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-20T01:00:00Z")
        let template = TaskTemplate(
            id: V0MigrationFixture.templateID, title: "合成原版模板", iconName: "book.fill", colorToken: "reading",
            targetDurationSeconds: 900, createdAt: now, updatedAt: now)
        let rule = ReminderRule(
            id: V0MigrationFixture.ruleID, taskTemplateID: template.id,
            recurrence: .once(on: try V0MigrationFixture.date("2026-09-21")),
            timeOfDayMinutes: 19 * 60 + 30)
        context.insert(template)
        context.insert(rule)
        template.reminderRule = rule
        try context.save()
    }

    private func verifyFrozenStore(at url: URL, timerState: TimerSessionState, versioned: Bool) throws {
        let context = ModelContext(try V0MigrationFixture.container(at: url, versioned: versioned))
        let templates = try context.fetch(FetchDescriptor<HabitoSchemaV0.TaskTemplate>())
        let occurrences = try context.fetch(FetchDescriptor<HabitoSchemaV0.TaskOccurrence>())
        let template = try #require(templates.first { $0.id == V0MigrationFixture.templateID })
        let completed = try #require(occurrences.first { $0.id == V0MigrationFixture.completedID })
        let active = try #require(occurrences.first { $0.id == V0MigrationFixture.activeID })
        let orphan = try #require(occurrences.first { $0.id == V0MigrationFixture.orphanID })
        let settings = try #require(context.fetch(FetchDescriptor<HabitoSchemaV0.AppSettings>()).first)
        #expect(templates.count == 2 && occurrences.count == 4)
        #expect(template.title == "合成阅读" && template.revision == 2 && template.occurrences.count == 3)
        #expect(template.reminderRule?.taskTemplate?.id == template.id)
        #expect(template.reminderRule?.weekdays == [.monday, .tuesday, .wednesday])
        #expect(template.reminderRule?.timeOfDayMinutes == 19 * 60 + 30)
        #expect(templates.first { $0.id == V0MigrationFixture.archivedTemplateID }?.lifecycleState == .archived)
        #expect(completed.titleSnapshot == "合成旧阅读" && completed.status == .completed)
        #expect(completed.completionRecord?.completionSource == .childManual)
        #expect(completed.completionRecord?.occurrence?.id == completed.id)
        #expect(completed.completionRecord?.activeDurationSeconds == 900)
        #expect(completed.timerSessions.first?.state == .ended)
        #expect(completed.timerSessions.first?.endedAt == completed.completionRecord?.completedAt)
        #expect(active.isDetachedOverride && active.titleSnapshot == "合成单日阅读")
        #expect(
            active.uniquenessKey
                == HabitoSchemaV0.TaskOccurrence.makeUniquenessKey(templateID: template.id, dateKey: "2026-09-22"))
        #expect(active.status == .inProgress && active.targetDurationSnapshot == 1800)
        #expect(active.timerSessions.first?.state == timerState)
        #expect(
            active.timerSessions.first?.accumulatedActiveSeconds == 300 && active.timerSessions.first?.endedAt == nil)
        #expect(active.timerSessions.first?.lastResumedAt == (try V0MigrationFixture.instant("2026-09-22T11:05:00Z")))
        #expect(active.notificationLinks.count == 2)
        #expect(Set(active.notificationLinks.compactMap(\.kind)) == [.primary, .snooze])
        #expect(active.notificationLinks.allSatisfy { $0.occurrence?.id == active.id })
        #expect(orphan.template == nil && orphan.completionRecord?.completionSource == .parentCorrection)
        #expect(settings.hasParentPIN && settings.parentPINCredentialKey == AppSettings.parentPINKeychainAccount)
        #expect(settings.schemaVersion == 1 && settings.isOnboardingCompleted)
        #expect(
            settings.schedulingHorizonDateKey == "2026-09-28" && settings.lastNotificationAuthorization == .authorized)
        #expect(try context.fetchCount(FetchDescriptor<HabitoSchemaV0.ReminderRule>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<HabitoSchemaV0.CompletionRecord>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<HabitoSchemaV0.TimerSession>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<HabitoSchemaV0.NotificationLink>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<HabitoSchemaV0.DayOverride>()) == 2)
    }

    private func verifyCurrentStore(at url: URL, timerState: TimerSessionState) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
        let active = try #require(occurrences.first { $0.id == V0MigrationFixture.activeID })
        let completed = try #require(occurrences.first { $0.id == V0MigrationFixture.completedID })
        let orphan = try #require(occurrences.first { $0.id == V0MigrationFixture.orphanID })
        let settings = try #require(context.fetch(FetchDescriptor<AppSettings>()).first)
        let overrides = try context.fetch(FetchDescriptor<DayOverride>())
        #expect(templates.count == 2 && occurrences.count == 4 && overrides.count == 2)
        #expect(active.template?.id == V0MigrationFixture.templateID && active.template?.occurrences.count == 3)
        #expect(active.template?.reminderRule?.taskTemplate?.id == V0MigrationFixture.templateID)
        #expect(active.template?.reminderRule?.timeOfDayMinutes == 19 * 60 + 30)
        #expect(active.isDetachedOverride && active.titleSnapshot == "合成单日阅读" && active.targetDurationSnapshot == 1800)
        #expect(
            active.timerSessions.first?.state == timerState
                && active.timerSessions.first?.accumulatedActiveSeconds == 300)
        #expect(active.timerSessions.first?.lastResumedAt == (try V0MigrationFixture.instant("2026-09-22T11:05:00Z")))
        #expect(active.notificationLinks.count == 2)
        #expect(
            Set(active.notificationLinks.map(\.requestIdentifier))
                == Set(
                    [NotificationKind.primary, .snooze].map {
                        NotificationRequestIdentifier(occurrenceID: active.id, kind: $0).rawValue
                    }))
        #expect(completed.status == .completed && completed.titleSnapshot == "合成旧阅读")
        #expect(completed.completionRecord?.completedAt == (try V0MigrationFixture.instant("2026-09-21T11:45:00Z")))
        #expect(
            completed.completionRecord?.occurrence?.id == completed.id && completed.timerSessions.first?.state == .ended
        )
        #expect(orphan.template == nil && orphan.completionRecord?.completionSource == .parentCorrection)
        #expect(overrides.first { $0.dateKey == "2026-09-22" }?.dayType == .holiday)
        #expect(overrides.first { $0.dateKey == "2026-09-21" }?.note == "合成上课覆盖")
        #expect(settings.hasParentPIN && settings.parentPINCredentialKey == AppSettings.parentPINKeychainAccount)
        #expect(settings.lastInstanceGenerationAt == (try V0MigrationFixture.instant("2026-09-22T11:10:00Z")))
        #expect(settings.lastNotificationSchedulingAt == settings.lastInstanceGenerationAt)
        #expect(settings.schemaVersion == 1 && settings.lastNotificationAuthorization == .authorized)
        #expect(try context.fetchCount(FetchDescriptor<ReminderRule>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<TimerSession>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<NotificationLink>()) == 2)
    }
}
