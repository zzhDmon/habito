import SwiftData

/// 独立冻结的结构 3.0.0：八个任务模型与两个账本模型，不能随当前模型演进。
nonisolated enum HabitoSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
            XPTransaction.self, CoinTransaction.self,
        ]
    }
}
