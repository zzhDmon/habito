import SwiftData

/// 独立冻结的完成审计结构 4.0.0；十模型不随当前字段演进。
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
