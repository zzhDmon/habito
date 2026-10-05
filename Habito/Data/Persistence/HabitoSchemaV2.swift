import SwiftData

/// 在结构 2.0.0 基础上增加空 XP/Coin 审计账本，不在迁移时补发历史奖励。
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
