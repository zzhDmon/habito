import SwiftData

/// 宠物事实结构9.0.0；只增喂食审计和反馈观察点，不回填等级、亲密度或历史喂食。
nonisolated enum HabitoSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskTemplate.self, ReminderRule.self, TaskOccurrence.self, CompletionRecord.self,
            TimerSession.self, DayOverride.self, NotificationLink.self, AppSettings.self,
            XPTransaction.self, CoinTransaction.self, TaskSubmission.self, ChildProfile.self, Pet.self,
            PetFeeding.self, PetGrowthCheckpoint.self,
        ]
    }
}
