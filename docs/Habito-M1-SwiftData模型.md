# Habito M1 SwiftData 模型

> 本文记录 M1-002 的持久化边界。业务状态语义以《Habito-M1-领域类型与状态机》为准。

## 模型与关系

| 模型 | 归属关系 | 删除规则 |
|---|---|---|
| `TaskTemplate` | 拥有一个 `ReminderRule`，关联多个 `TaskOccurrence` | 产品只软删除；维护性物理删除时规则级联、实例关系置空 |
| `ReminderRule` | 属于模板，同时保留 `taskTemplateID` | 随模板物理删除 |
| `TaskOccurrence` | 可选关联来源模板，拥有完成记录、计时会话和通知映射 | 物理删除时拥有的数据级联删除 |
| `CompletionRecord` | 一个实例最多一条 | 随实例物理删除 |
| `TimerSession` | 一个实例可有多个历史会话 | 随实例物理删除；“最多一个未结束”由 M1-006 事务保证 |
| `DayOverride` | 按本地日期独立存在 | 直接增删 |
| `NotificationLink` | 属于任务实例 | 随实例物理删除，也可在通知核对时单独删除 |
| `AppSettings` | 单设备单例 | 不与业务模型级联 |

关系均同时保留稳定 UUID，避免关系置空后失去审计线索。历史展示依赖实例快照，不依赖模板仍然存在。

## 唯一性与查询

- 所有 UUID 主键使用 `@Attribute(.unique)`。
- `ReminderRule.taskTemplateID` 唯一，确保一个模板最多一个规则。
- `TaskOccurrence.uniquenessKey` 使用小写模板 UUID 与 `dateKey` 组合，兼容 iPadOS 17 不提供复合唯一约束的限制。
- `CompletionRecord.occurrenceID` 唯一，确保一个实例最多一条当前完成记录。
- `DayOverride.dateKey`、`NotificationLink.requestIdentifier` 与 `AppSettings.singletonKey` 分别唯一。
- V0 不接 CloudKit，因此可以使用 SwiftData 唯一属性；若未来接入 CloudKit，必须改为应用层合并策略。
- 高频查询使用持久化标量字段：`templateID`、`occurrenceID`、`dateKey`、`scheduledAt`、状态原始值。iPadOS 17 没有后续系统版本的声明式 `#Index`，当前由唯一索引和小数据量假设支撑。

## PIN 与敏感数据

`AppSettings` 不保存 PIN 明文、摘要或盐，只保存 Keychain 条目的非敏感查找键。实际凭据写入、验证和重置由 M3-001 的 Keychain 服务实现。
