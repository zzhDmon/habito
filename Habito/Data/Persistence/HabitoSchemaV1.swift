import SwiftData

/// V1 第一版增量的历史 schema；独立冻结结构 2.0.0，不能跟随当前模型一起改字段。
///
/// 模型定义位于 SchemaV1 的分文件扩展；未接入业务/UI 的字段不会自动发奖。
nonisolated enum HabitoSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
        ]
    }
}
