import SwiftData

/// 稍后排程世代结构 6.0.0；旧映射保持空提交 ID，不猜测或补发原请求。
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
