import SwiftData

/// 冻结的名字资料结构8.0.0；独立嵌套模型保持历史字段、名字和关系，不引用活跃模型。
nonisolated enum HabitoSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
            XPTransaction.self, CoinTransaction.self, TaskSubmission.self, ChildProfile.self, Pet.self,
        ]
    }
}
