# Habito V1 迁移验收记录

## 1. V1-M1-001：冻结旧 schema 与合成磁盘库

- 原始模型基线：`1b5591b`。冻结于 `Habito/Data/Persistence/SchemaV0`，每个模型独立文件，置于 HabitoSchemaV0 命名空间；不是指向当前模型的 typealias。
- 源定义字段、默认值、唯一约束、关系和删除规则保持不变。机械提取后用 `diff -w` 与该 commit 的八个源文件逐一对照通过，只有命名空间/文件说明与缩进变化。测试固定检查八实体和完整属性名；未来不得把冻结模型也一起加 V1 字段。
- VersionedSchema 描述结构，容器/上下文仍由主 actor 管理。版本 1.0.0 是原八模型基线，AppSettings.schemaVersion 不是 SwiftData 迁移元数据。参考 [Apple WWDC23 Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/) 与 [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema)；示例不代替以下实际兼容测试。
- 合成图：两个模板（启用/归档）、四实例（完成、单日 detached 活动、普通待完成、模板已缺失的历史）、两完成、两计时、两个通知槽位、上课/放假覆盖、设置和固定 Keychain 查找引用。没有真实 PIN、凭据、家庭数据或设备标识。
- 测试在随机临时路径创建真实 SQLite 磁盘库；业务日期、字段和 UUID 固定。不会读取系统当前时间、等待计时器或访问真实 Keychain。SwiftData 无显式 close，旧系统可能延迟释放；不删除仍连接的 SQLite/WAL，目录交由测试沙箱清理。
- 双系统专项 **4/4（10 次参数执行）通过**：运行/暂停 × 非版本/版本 schema 生成，连续两次冻结库重开；当前 V0 连续两次读取冻结库；原 App 非版本 schema 生成的库反向由冻结模型读取。命名空间是否改变磁盘兼容由该测试实证，不仅对比内存对象。
- 首轮专项结果：iOS 17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_21-46-06-+0800.xcresult`；iOS 27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_21-46-06-+0800.xcresult`。均零失败/跳过/runtime warning。
- 随后补齐原 App 写入用例的固定规则 ID，最终完整单测各 **197/197（232 次执行）通过**：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_21-47-43-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_21-47-44-+0800.xcresult`。零失败/跳过/runtime warning，已核对摘要，不仅依据退出码。
- 静态分析与 Release iPad 横屏 Simulator 工程构建通过；全工程严格格式、plist 解析、差异检查通过。swiftui-pro 部分复核检查模型边界、中文 DocC、主 actor 与不跨容器传对象，无第三方依赖或关闭并发检查。
- 此阶段正式 AppModelContainer 和当前模型未改、未添加奖励。还没有 V1 schema 迁移证据，没有实际家庭旧库或真机送达证据。后续 M1-002 从此独立旧库生成器验证真正 schema 演进，不能把“当前新模型自己写自己读”冒充旧库迁移。

### 原始源文件 SHA-256

以下是 `1b5591b` 的原始文件内容校验，不是 SwiftData 内部实体 checksum；不能拿它判断两个 schema 兼容。

| 模型 | 原文件 SHA-256 |
|---|---|
| TaskTemplate | aba9f3457a39452b9e16bdc175ed85f0297971bafbbfec79c43bca6c806b5a69 |
| ReminderRule | a77766111d597b412da29cd88e658ed8b45b8cc01336a1959e6eca2bfe7ee8bf |
| TaskOccurrence | 5eaff5352f562f11df7288c720d2d9f2f514cff107f6d5d1909d7950d105e035 |
| CompletionRecord | 2ca6882f3c9561e81e784e17637021f157d10db0eebb84da999e8d497bc1837c |
| TimerSession | c868889093c606b6a3aad3f687b5b5fa6d4426b947d633acab75873ec5308e1f |
| DayOverride | 628fe01b64c1d8b625b2592e33aebdf578a6b53801b0dcc107cd71365feb4937 |
| NotificationLink | 88e35fc3184b6e090acbbc1bde8d1aea4dfb020f5bde7df71d0f7e6f968c1058 |
| AppSettings | 2707162b902ca3519590304f494181cf1a35432c554abc3cd89f2beccfd7f99c |
