import SwiftData

/// 已发布 V0 八模型的独立历史定义，供合成旧库及后续迁移计划使用。
///
/// `VersionedSchema` 只描述模型，不拥有容器或上下文；实际读写仍由调用方的 actor 管理。
/// - Important: 不能用当前模型的 typealias 代替这些冻结类型，否则新增 V1 字段也会改变旧库。
///   版本号描述 schema 结构，不是 AppSettings.schemaVersion 的业务检查点。
nonisolated enum HabitoSchemaV0: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
        ]
    }
}
