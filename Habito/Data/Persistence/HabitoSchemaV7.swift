import SwiftData

/// 名字资料结构 8.0.0；只增加两个独立资料实体，不自动为旧家庭创建档案或小狗。
///
/// 活跃模型归属主 actor 的写上下文，等级、亲密度、情绪与消费结构尚未启用。
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
