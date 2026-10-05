import SwiftData

/// 家长提交审计结构 5.0.0；旧任务和奖励原样保留，不生成旧提交或补发奖励。
nonisolated enum HabitoSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
            XPTransaction.self, CoinTransaction.self, TaskSubmission.self,
        ]
    }
}
