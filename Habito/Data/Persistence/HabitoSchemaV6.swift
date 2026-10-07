import SwiftData

/// 儿童收据投递结构 7.0.0；旧完成保持未启用，不补弹历史反馈或重算奖励。
///
/// 投递元数据只描述展示生命周期，当前业务模型归属调用方的主 actor 上下文。
nonisolated enum HabitoSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
            XPTransaction.self, CoinTransaction.self, TaskSubmission.self,
        ]
    }
}
