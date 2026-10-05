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

## 2. V1-M1-002：兼容字段与显式轻量迁移

- HabitoSchemaV1 使用结构版本 2.0.0，显式计划从独立 HabitoSchemaV0 的 1.0.0 演进。正式容器组合根接入该计划；没有删库重建、迁移失败重试覆盖或真实家庭库读取。AppSettings.schemaVersion 原业务值保持 1，不冒充 SwiftData 版本元数据。
- 模板新增分类/时间段/验收原始值及三项显式奖励配置；实例有对应独立快照和可空计划/截止；规则保留原提醒字段并增可空计划/截止分钟；完成增加自主性原始值。兼容默认只为 unassigned/allDay/selfConfirm/0/unknown，未预埋分类奖励、食物或宠物参数。
- 领域四类型独立文件、英文标识和中文 DocC；无效原始值返回 nil，不用合法旧库默认掩盖损坏。自主判定纯函数只接受提交与提醒快照，严格早于才自主。
- 冻结 V0 保持不变。原第一阶段的“当前 V0 反向读取”已取得历史证据；当前 App 已演进，旧生成器必须继续使用独立 V0 类型，不能使用更新后的 AppModelContainer 冒充原 schema。原先对象图重开测试继续验证完整旧字段、关系和稳定 ID，不删除以掩盖迁移问题。
- 专项双系统各 **10/10（20 次执行）通过**，包含旧库/空库的非版本与版本元数据、新库显式配置持久化/模板编辑后实例保持、损坏原始值、三个时间边界、损坏磁盘文件拒绝且主文件不变，以及冻结 schema 的完整对象图回归。17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_21-58-39-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_21-58-40-+0800.xcresult`；零失败/跳过/runtime warning。
- 完整单测双系统各 **203/203（242 次执行）通过**，零失败/跳过/runtime warning：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_21-59-59-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-00-00-+0800.xcresult`。静态分析、Release 横屏构建、严格格式与工程解析通过；完整横屏 UI 收尾中。
- 不将数据层快照当成业务提交事务：当前 UI 仍是 V0 完成入口，实际新提交自主性写入、奖励结算、提交历史与家长验收在后续用例卡接入。此阶段只提供可持久化参数和纯判定，不宣称验收/奖励已可用；测试的 11/7/3 等显式输入不是产品默认。
- 下次模型变更前要先冻结本版八模型，避免当前 HabitoSchemaV1 的类型随未来字段变化而改写结构版本 2.0.0。后续账本 schema 卡必须以稳定旧版本为输入，保留这次迁移结果再验证。
- 最终横屏 UI 双系统各 **16/16**，零失败/跳过：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_22-00-33-+0800.xcresult`（238.422 秒，无 runtime warning）；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-00-34-+0800.xcresult`（322.026 秒，保留 16 条 R-009 全屏方向提示）。未以 UI 点击桥代替系统送达，未以成功命令代替断言数量。swiftui-pro 复核数据流、严格并发和系统边界通过，App UI 本次未新增页面。

## 3. V1-M1-003A：冻结上一版与空交易账本

- 从 `da08d63` 独立冻结结构 2.0.0 的八模型到 SchemaV1 分文件命名空间；逐一 `diff -w` 对照通过，字段、关系、默认值未改。V0 定义保持不变。当前结构 3.0.0 只增加 XPTransaction/CoinTransaction，显式轻量迁移顺序为 1 → 2 → 3。
- 交易字段对外只读，来源用 UUID 与业务键反查，不建立任务图级联关系。唯一约束只是存储兜底，不代表业务幂等；模型初始化尚不验证余额/冲正语义，未开放 UI 或业务写入口，下一卡负责验证。合成模型测试故意允许低层有符号金额，不能据此宣称可以负余额消费。
- 真实 SQLite 专项涵盖非版本/版本 V0 → 当前、独立结构 2 → 当前、连续重开、非零配置/历史保留但账本为空、交易身份/来源/类型/冲正关联持久化，以及删除合成实例后交易保留。PIN 只验证非敏感引用，未读 Keychain 或家庭数据。
- 开发时夹具错误地直接设置只读 PIN 字段，编译拒绝；已改用冻结模型既有 `hasParentPIN` 初始化参数，不放宽正式模型或冻结定义。修前两个系统构建失败不是迁移失败，也不算通过证据。
- 修后两系统专项各 **14/14（25 次执行）通过**，零失败/跳过/runtime warning：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_22-19-49-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-19-50-+0800.xcresult`。全量和构建验收正在进行，不提前标记整卡 DONE。
- 最终完整单测两系统各 **207/207（247 次执行）通过**，零失败/跳过/runtime warning：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_22-20-29-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-20-30-+0800.xcresult`。Release 横屏工程构建、静态分析、全工程严格格式、工程解析及差异检查通过，003A DONE。无新 UI 或真机送达证据；上一卡 UI 通过不重写成此次新证据。

## 4. V1-M1-004A：完成快照与多次审计兼容结构

- 结构 3.0.0 的十模型独立冻结自 `45a7172`，逐一机械 `diff -w` 对照通过；1.0.0/2.0.0 定义未动。当前结构 4.0.0 增完成记录的提醒/XP/基础 Coin/自主加成/实际 Coin 快照、结算版本和撤销时刻。
- 旧字段保持，新增提醒/撤销时刻为空、金额/结算版本为零，旧自主性原值不改。即使已有账本，也不从它倒灌新快照或把旧事实冒充新事务结算；不补奖。新提交包括零奖励旧任务将由后续用例正常判断，unknown 仅保护旧历史证据不足。
- 保留完成 ID 唯一；移除 occurrenceID 的存储唯一约束，以便原撤销记录与新完成共存。TaskOccurrence.completionRecord 仍单值，指向当前未撤销事实；撤销历史可断开活跃关系但稳定外键保留。活动事实唯一性由后续业务事务校验。旧 App 写路径尚未切换，不创建新多记录历史，不声明新奖励 UI 可用。
- Apple 示例说明新增唯一约束需要特别迁移处理，不据此推断移除约束必然兼容；本项目以独立真实磁盘旧库与双系统验证为准。[Apple WWDC23 schema migration](https://developer.apple.com/videos/play/wwdc2023/10195/)
- 首轮迁移专项两系统各 **16/16（29 次）通过**：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_22-40-45-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-40-46-+0800.xcresult`，零失败/跳过/runtime warning。随后补固定账本交易 ID 断言，最终全量同时覆盖。
- 最终完整单测两系统各 **226/226（279 次）通过**：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_22-41-58-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-41-59-+0800.xcresult`，零失败/跳过/runtime warning。Release 横屏构建、静态分析、严格格式、工程解析与差异检查通过；完整 UI 在运行，整卡仍 IN_PROGRESS。
- 新测试只验证合成结构允许多条历史，未实现真实撤销/重完事务；没有把手工模型写入说成发奖或冲正完成。未来 004B/005/006 的原子写入、计时、窗口、通知和入口各有验收。未读取家庭库、真实 PIN 或修改真机包。
- 补齐“改单日提醒/奖励不能改写已提交快照”后，最终全量重新运行，两系统仍各 **226/226（279 次）**，零失败/跳过/runtime warning：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_22-47-32-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-48-32-+0800.xcresult`。
- 完整横屏 UI 各 **16/16**，零失败/跳过：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_22-42-45-+0800.xcresult`（237.437 秒、无 runtime warning）；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_22-42-46-+0800.xcresult`（319.146 秒、保留 16 条 R-009）。自动化桥仍不代替真机送达证据。swiftui-pro 数据/并发/卫生复核与严格格式通过，004A DONE。

## 5. V1-M3-001A：家长提交审计兼容结构

- 从 6ac9c83 独立冻结结构 4.0.0 十模型到 SchemaV3；逐一提取后去除命名空间缩进与源文本机械核对通过，字段/约束/关系/默认未变。1～3 结构定义未动。当前结构 5.0.0 增 TaskSubmission，完成事实新增可空 submissionID/rewardSettledAt；迁移顺序明确 1 → 2 → 3 → 4 → 5。
- 每次提交有稳定 ID/实例外键、递增序号和业务键、原提交/提醒/奖励/时长快照及 waiting/approved/returned 结果。提交快照外部只读，审核结果由后续用例维护；同时间提交用序号区分，不靠时间排序。没有级联关系，实例删除不抹掉提交审计；待审核实例保护由 003 接入，不在本卡开放提交入口。
- completedAt 保留孩子真实提交事实，rewardSettledAt 单列家长实际结算时刻；自主性绝不使用审核时间。旧记录两个新增字段均空，不补造旧提交、审核或奖励，不改旧任务 status 原始值；等待状态以后由提交事实派生，不另建一套可漂移任务状态。
- 独立 V0/2.0.0/3.0.0/4.0.0 SQLite 迁移与三次重开：原完成 ID/关系、已发及已冲正账本的稳定交易 ID/金额、撤销记录、暂停计时、PIN 非敏感引用保持；提交为空。另覆盖空旧库、合成多次提交/审核关联/快照重开、相同提交时刻、实例删除保留审计、waiting 零奖励重开仍无完成与无到账且自主已知。
- 手工合成审核关联只证明结构持久化，不冒充真实通过/结算事务，尤其不因关联存在就补账；001B/002 将验证计时、状态、奖励的一次保存。无家庭 DB、真实 Keychain 或旧包操作，未设置默认产品数值。
- 注册阶段曾误将 SchemaV3 group 放入 source build phase，两系统工程解析失败、尚未执行测试；已修为 group 只在目录树，源码列表只放 BuildFile。该失败不是迁移失败、不算通过；随后真实双系统迁移专项各 **14/14（23 次）通过**：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.05_23-58-45-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.05_23-58-47-+0800.xcresult`，零失败/跳过/runtime warning。
- 后补固定交易 ID 与 waiting 重开断言后，最终完整两系统各 **270/270（335 次）通过**：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.06_00-05-53-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.06_00-07-25-+0800.xcresult`，零失败/跳过/runtime warning。
- 完整横屏 UI 各 **16/16**：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.06_00-00-53-+0800.xcresult`（235.166 秒，无 runtime warning）；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.06_00-00-54-+0800.xcresult`（318.298 秒，保留 16 条 R-009），零失败/跳过。UI 后仅补结构单测及修正失效注释，没有改 App 行为或布局；最终单测再次运行覆盖新增断言。
- Release 横屏构建、静态分析、严格格式、工程解析/差异检查通过；swiftui-pro 数据/Swift/卫生复核保持主 actor 模型/上下文、固定时间、原生 SwiftData、稳定外键与中文 DocC，更新当前撤销字段失效注释，不改冻结历史。001A DONE；待验收 UI、审批事务和更强反馈仍未完成，V0 真机 B 不放行。

## 6. V1-M3-003B0：稍后验收世代兼容结构

- 从 7c8b5ac 独立冻结结构 5.0.0 十一模型到 SchemaV4。逐一去除命名空间/导入/注释与格式空白后机械核对源正文相同，字段、约束、关系、默认值未变；结构 1～4 未动。当前结构 6.0.0 仅新增 NotificationLink.submissionIDAtScheduling 可空 UUID，显式轻量迁移 5 → 6。
- 原 stable identifier、排程时刻、首次 createdAt 保持；旧映射的新属性 nil，不用时间猜所属提交轮次。实际稍后写入与重建世代校验归 003B，本卡不改变系统排程行为、不访问真实家庭库或通知队列。
- 独立旧 5 SQLite 夹具包含退回后再通过、真实提交/次日审核两个时刻、版本 2 完成与成对奖励、已冲正历史完成与原交易 ID、待验收、暂停/结束计时、主/稍后映射、日期覆盖和 PIN 非敏感查找引用。完整与空库迁移三次重开；可空世代写明确 ID 或保持 nil 后两次重开；四版更早旧库不凭空补提交/世代/奖励。
- 双系统专项各 **14/14（26 次）通过**，零失败/跳过/runtime warning：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.06_01-20-24-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.06_01-20-25-+0800.xcresult`。审核历史、完成快照、余额、冲正、计时与稳定通知标识实际断言通过，不只是能打开数据库。
- 最终完整单测各 **320/320（422 次）通过**，零失败/跳过/runtime warning：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.06_01-21-05-+0800.xcresult`；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.06_01-21-06-+0800.xcresult`。Release 横屏构建、静态分析、严格格式、工程解析/差异检查通过；完整横屏 UI 回归仍在运行，本卡保持 IN_PROGRESS。
- swiftui-pro 数据/Swift/卫生部分复核保持主 actor SwiftData、独立冻结模型、明确失败、固定时刻和随机隔离磁盘库。没有新默认奖励、宠物数值、第三方依赖、家庭库迁移或实际送达证据；强反馈和验收 UI 后续独立完成。
- 最终完整横屏 UI 各 **16/16**，零失败/跳过：17.2 `/tmp/habito-v1-m1-001-ios17/Logs/Test/Test-Habito-2026.10.06_01-21-55-+0800.xcresult`（237.929 秒、无 runtime warning）；27 `/tmp/habito-v1-m1-001-ios27/Logs/Test/Test-Habito-2026.10.06_01-21-56-+0800.xcresult`（320.389 秒、16 条已登记 R-009 全屏方向提示）。003B0 DONE，后续通知行为由 003B 独立验证，不把兼容字段持久化冒充通知清理完成。
