# Habito M1 领域类型与状态机

> 本文是 M1-001 的业务语义基线。后续 SwiftData、Service 和 UI 必须复用这些领域类型，不得另行发明状态。

## 本地日期与重复规则

- `LocalDate` 只表示本地日历中的年月日，不带时区和具体时刻；持久化键固定为 `yyyy-MM-dd`。
- 从 `Date` 提取日期时必须显式传入 `Calendar` 和 `TimeZone`，测试不得依赖设备当前值。
- `TaskRecurrence` 只支持 `once` 与 `weekly`。一次性规则只有一个日期；每周规则至少一个星期，结束日期不得早于开始日期。
- `Weekday` 的原始值与 Apple `Calendar` 一致：星期日为 1，星期六为 7。

## 任务实例状态

| 当前状态 | 动作 | 新状态 | 说明 |
|---|---|---|---|
| `pending` | `start` | `inProgress` | 首次开始计时 |
| `pending` | `complete` | `completed` | 支持不计时直接打卡或家长更正 |
| `pending` | `skip` | `skipped` | 只允许尚未开始的实例跳过 |
| `inProgress` | `complete` | `completed` | 完成时由 M1-006 结束活动计时会话 |
| `skipped` | `restore` | `pending` | 家长恢复当天任务 |
| `completed` | `undoCompletion` | `pending` | 撤销完成记录，但不复活已经结束的计时会话 |

表中未列出的转换全部非法，并抛出 `DomainStateTransitionError`。暂停中的实例仍是 `inProgress`，暂停状态只记录在计时会话中。

## 计时会话状态

| 当前状态 | 动作 | 新状态 |
|---|---|---|
| `running` | `pause` | `paused` |
| `paused` | `resume` | `running` |
| `running` / `paused` | `end` | `ended` |

`ended` 是不可恢复终态。重复暂停、重复继续、重复结束均视为调用错误，不能静默成功。

## 模板生命周期与软删除

| 当前状态 | 动作 | 新状态 |
|---|---|---|
| `active` | `disable` | `disabled` |
| `disabled` | `enable` | `active` |
| `active` / `disabled` | `archive` | `archived` |

`archived` 表示软删除且不可恢复。归档模板只停止未来生成并触发未来未开始实例清理；历史实例和完成记录必须保留。

## 完成与单日覆盖语义

- `CompletionSource.childManual` 表示孩子主动打卡，`parentCorrection` 表示家长更正；来源与实例状态分开保存。
- `TaskOccurrenceOrigin.generated(templateRevision:)` 记录生成时的模板版本，可参与未来模板修订。
- `TaskOccurrenceOrigin.detachedOverride` 表示当天独立修改、恢复或新增，后续模板编辑不得覆盖。
- 放假日只移除尚未开始的普通生成实例；已开始、已完成、已跳过和单日覆盖实例的具体合并规则由 M1-004 实现。
