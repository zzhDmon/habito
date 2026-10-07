import SwiftData

/// 冻结的结构 6.0.0，包含稍后世代与可空计划/截止；不引用当前活跃模型。
nonisolated enum HabitoSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
            XPTransaction.self, CoinTransaction.self, TaskSubmission.self,
        ]
    }
}
