import SwiftData

/// 独立冻结的提交审计结构 5.0.0；十一模型不随当前稍后世代字段演进。
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
