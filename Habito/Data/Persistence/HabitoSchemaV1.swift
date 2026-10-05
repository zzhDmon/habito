import SwiftData

/// V1 第一版增量 schema；包含兼容字段，但不代表奖励/验收用例已接入 UI。
///
/// 旧定义由独立 HabitoSchemaV0 固定；当前八类型继续供原用例使用，避免全工程改名。
nonisolated enum HabitoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
        ]
    }
}
