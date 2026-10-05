import SwiftData

/// 按 V0 → V1 兼容字段 → 空账本 → 完成审计的明确顺序演进，不在打不开时删库重建。
///
/// 增量字段采用零/合法默认或可空值；完成审计还移除实例外键 unique，双系统磁盘迁移已验证。
/// 所有历史时间、ID、关系及 Keychain 引用保持。迁移只随容器打开，不访问真实凭据。
nonisolated enum HabitoSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [HabitoSchemaV0.self, HabitoSchemaV1.self, HabitoSchemaV2.self, HabitoSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: HabitoSchemaV0.self, toVersion: HabitoSchemaV1.self),
            .lightweight(fromVersion: HabitoSchemaV1.self, toVersion: HabitoSchemaV2.self),
            .lightweight(fromVersion: HabitoSchemaV2.self, toVersion: HabitoSchemaV3.self),
        ]
    }
}
