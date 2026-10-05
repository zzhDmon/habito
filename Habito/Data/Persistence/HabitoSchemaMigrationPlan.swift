import SwiftData

/// 按旧任务 → 配置 → 账本 → 完成审计 → 提交审计 → 稍后世代演进，不删库重建。
///
/// 增量字段采用零/合法默认或可空值；完成审计还移除实例外键 unique，双系统磁盘迁移已验证。
/// 所有历史时间、ID、关系及 Keychain 引用保持。迁移只随容器打开，不访问真实凭据。
nonisolated enum HabitoSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            HabitoSchemaV0.self, HabitoSchemaV1.self, HabitoSchemaV2.self, HabitoSchemaV3.self, HabitoSchemaV4.self,
            HabitoSchemaV5.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: HabitoSchemaV0.self, toVersion: HabitoSchemaV1.self),
            .lightweight(fromVersion: HabitoSchemaV1.self, toVersion: HabitoSchemaV2.self),
            .lightweight(fromVersion: HabitoSchemaV2.self, toVersion: HabitoSchemaV3.self),
            .lightweight(fromVersion: HabitoSchemaV3.self, toVersion: HabitoSchemaV4.self),
            .lightweight(fromVersion: HabitoSchemaV4.self, toVersion: HabitoSchemaV5.self),
        ]
    }
}
