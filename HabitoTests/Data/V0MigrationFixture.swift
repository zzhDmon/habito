import Foundation
import SwiftData
@testable import Habito

/// 只用独立冻结 V0 类型生成旧磁盘库，不读取家庭数据或真实 Keychain。
///
/// 容器与对象图由主 actor 独占；跨容器只传文件 URL 和固定业务 ID，不传模型对象。
@MainActor
enum V0MigrationFixture {
    static let templateID = id(1)
    static let ruleID = id(2)
    static let completedID = id(3)
    static let activeID = id(6)
    static let pendingID = id(8)
    static let archivedTemplateID = id(11)
    static let orphanID = id(12)

    /// 按已发布的非版本 schema 形态创建磁盘容器，或显式验证同结构的版本描述。
    ///
    /// - Parameters:
    ///   - storeURL: 本次测试专属临时磁盘位置，不能传正式容器位置。
    ///   - versioned: 是否带版本描述；旧 App 原本使用非版本 schema，两条路径均需覆盖。
    /// - Returns: 只包含八个冻结 V0 模型的容器。
    /// - Throws: SwiftData 容器创建错误，不进行删库重试。
    static func container(at storeURL: URL, versioned: Bool = false) throws -> ModelContainer {
        let schema = versioned ? Schema(versionedSchema: HabitoSchemaV0.self) : Schema(HabitoSchemaV0.models)
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
    }

    /// 建立包含历史、活动计时、单日覆盖、归档与无模板历史的合成对象图。
    ///
    /// - Parameters:
    ///   - storeURL: 测试新建的临时路径。
    ///   - timerState: 活动会话为 running 或 paused；不依赖等待真实计时。
    ///   - versioned: 是否用显式版本元数据创建旧库。
    /// - Throws: 固定输入解析、磁盘创建或保存失败；不吞错，也不清理仍连接的 SQLite 文件。
    static func seed(at storeURL: URL, timerState: TimerSessionState = .paused, versioned: Bool = false) throws {
        let context = ModelContext(try container(at: storeURL, versioned: versioned))
        context.autosaveEnabled = false
        let createdAt = try instant("2026-09-20T01:00:00Z")
        let updatedAt = try instant("2026-09-22T11:10:00Z")
        let template = HabitoSchemaV0.TaskTemplate(
            id: templateID, title: "合成阅读", iconName: "book.fill", colorToken: "reading",
            targetDurationSeconds: 900, revision: 2, createdAt: createdAt, updatedAt: updatedAt)
        let rule = HabitoSchemaV0.ReminderRule(
            id: ruleID, taskTemplateID: templateID,
            recurrence: try .weekly(on: [.monday, .tuesday, .wednesday], starting: date("2026-09-21")),
            timeOfDayMinutes: 19 * 60 + 30)
        let archived = HabitoSchemaV0.TaskTemplate(
            id: archivedTemplateID, title: "合成归档", iconName: "star.fill", colorToken: "reading",
            targetDurationSeconds: 600, isEnabled: false, revision: 3,
            createdAt: createdAt, updatedAt: updatedAt, archivedAt: try instant("2026-09-21T12:00:00Z"))
        context.insert(template)
        context.insert(rule)
        context.insert(archived)
        // iPadOS 17 关系必须先入同一个 context，不能依赖新版框架的自动对象图插入行为。
        template.reminderRule = rule
        rule.taskTemplate = template

        let completed = try occurrence(id: completedID, day: "2026-09-21", status: .completed)
        let active = try occurrence(id: activeID, day: "2026-09-22", status: .inProgress, detached: true)
        let pending = try occurrence(id: pendingID, day: "2026-09-23", status: .pending)
        let orphan = try occurrence(id: orphanID, day: "2026-09-24", status: .completed, templateID: id(13))
        for occurrence in [completed, active, pending, orphan] { context.insert(occurrence) }
        for occurrence in [completed, active, pending] { occurrence.template = template }

        let completion = HabitoSchemaV0.CompletionRecord(
            id: id(4), occurrenceID: completedID, completedAt: try instant("2026-09-21T11:45:00Z"),
            activeDurationSeconds: 900, completionSource: .childManual,
            createdAt: createdAt, updatedAt: updatedAt)
        let orphanCompletion = HabitoSchemaV0.CompletionRecord(
            id: id(14), occurrenceID: orphanID, completedAt: try instant("2026-09-24T11:50:00Z"),
            activeDurationSeconds: 0, completionSource: .parentCorrection,
            createdAt: createdAt, updatedAt: updatedAt)
        context.insert(completion)
        context.insert(orphanCompletion)
        completed.completionRecord = completion
        completion.occurrence = completed
        orphan.completionRecord = orphanCompletion
        orphanCompletion.occurrence = orphan

        let ended = HabitoSchemaV0.TimerSession(
            id: id(5), occurrenceID: completedID, state: .ended,
            startedAt: completed.scheduledAt, lastResumedAt: completed.scheduledAt,
            accumulatedActiveSeconds: 900, endedAt: completion.completedAt)
        let ongoing = HabitoSchemaV0.TimerSession(
            id: id(7), occurrenceID: activeID, state: timerState,
            startedAt: try instant("2026-09-22T11:00:00Z"), lastResumedAt: try instant("2026-09-22T11:05:00Z"),
            accumulatedActiveSeconds: 300)
        context.insert(ended)
        context.insert(ongoing)
        ended.occurrence = completed
        ongoing.occurrence = active

        for kind in [NotificationKind.primary, .snooze] {
            let link = HabitoSchemaV0.NotificationLink(
                requestIdentifier: NotificationRequestIdentifier(occurrenceID: activeID, kind: kind).rawValue,
                occurrenceID: activeID, kind: kind,
                scheduledAt: kind == .primary ? active.scheduledAt : updatedAt.addingTimeInterval(600),
                createdAt: createdAt)
            context.insert(link)
            link.occurrence = active
        }
        context.insert(
            HabitoSchemaV0.DayOverride(
                id: id(9), date: try date("2026-09-21"), dayType: .schoolDay,
                note: "合成上课覆盖", updatedAt: updatedAt))
        context.insert(
            HabitoSchemaV0.DayOverride(
                id: id(10), date: try date("2026-09-22"), dayType: .holiday,
                note: "合成放假覆盖", updatedAt: updatedAt))
        context.insert(
            HabitoSchemaV0.AppSettings(
                isOnboardingCompleted: true, hasParentPIN: true,
                lastInstanceGenerationAt: updatedAt, lastNotificationSchedulingAt: updatedAt,
                schedulingHorizonDateKey: "2026-09-28", lastNotificationAuthorization: .authorized, schemaVersion: 1))
        try context.save()
    }

    /// 为每个测试创建独立路径；UUID 仅隔离文件，不影响业务预期。
    static func temporaryStoreURL() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 没有 SwiftData 显式 close；不能 unlink 仍可能延迟释放的 SQLite，交给测试沙箱清理。
        return directory.appending(path: "Habito-V0.store")
    }

    static func instant(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }

    static func date(_ value: String) throws -> LocalDate { try LocalDate(dateKey: value) }

    private static func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    private static func occurrence(
        id: UUID, day: String, status: TaskOccurrenceStatus, detached: Bool = false,
        templateID: UUID = templateID
    ) throws -> HabitoSchemaV0.TaskOccurrence {
        HabitoSchemaV0.TaskOccurrence(
            id: id, templateID: templateID, date: try date(day), scheduledAt: try instant("\(day)T11:30:00Z"),
            titleSnapshot: detached ? "合成单日阅读" : "合成旧阅读",
            iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: detached ? 1800 : 900,
            status: status, sourceRevision: 1, isDetachedOverride: detached,
            createdAt: try instant("2026-09-20T01:00:00Z"), updatedAt: try instant("2026-09-22T11:10:00Z"))
    }
}
