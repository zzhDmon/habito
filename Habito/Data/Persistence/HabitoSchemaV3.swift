import SwiftData

/// 完成审计结构 4.0.0；保留旧事实与空兼容字段，不迁移补奖或回算自主性。
nonisolated enum HabitoSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
            XPTransaction.self, CoinTransaction.self,
        ]
    }
}
