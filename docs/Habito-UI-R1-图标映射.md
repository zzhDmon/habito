# Habito UI-R1 图标映射与来源

> UI-R1-002A。固定Tabler Icons v3.49.0的outline版本，不跟随main漂移。本阶段只核对来源与规格，未引入App资源、包管理依赖或运行时SVG库。

## 固定来源

官方[版本发布页](https://github.com/tabler/tabler-icons/releases/tag/v3.49.0)、[版本源码](https://github.com/tabler/tabler-icons/tree/v3.49.0)、[许可证](https://github.com/tabler/tabler-icons/blob/v3.49.0/LICENSE)。已只读获取LICENSE及下列5个SVG，XML核验viewBox为0 0 24 24、stroke-width为2、round线帽。文件SHA-256与固定URL见[来源校验清单](ui-r1/tabler-source-check.json)，许可证副本见[Tabler LICENSE](ui-r1/tabler-LICENSE.txt)。采用MIT，随分发保留版权及许可文本；后续资源转换记录转换方法和派生文件校验值。

## 现有任务标识兼容

| 存储/草稿标识 | 中文语义 | 固定源文件 | 建议资源语义名 |
|---|---|---|---|
| book.fill | 阅读 | icons/outline/book.svg | taskReading |
| pencil.line | 书写/作业 | icons/outline/pencil.svg | taskWriting |
| figure.run | 运动 | icons/outline/run.svg | taskActivity |
| music.note | 音乐 | icons/outline/music.svg | taskMusic |
| 未知/缺失旧图标 | 通用任务 | icons/outline/checklist.svg | taskGeneric |

存储值继续使用现有tag；新增展示适配器在边界映射，任务标题始终可见，未知标识用通用任务图标，绝不猜测任务类别或覆盖历史值。任务编辑Picker的tag不随新资源名变化。当前四类图标不扩展为新的任务分类/快捷模板需求。

## 图标分工

- 任务主视觉统一Tabler outline；正常显示24～32 pt，重点任务可40 pt，stroke跟随整体等比缩放，避免混用fill/outline和另一套图标库。
- 系统返回/关闭/锁定/设置/编辑等继续SF Symbols；它们不与任务卡主图标竞争。状态以中文+图标表达，颜色只辅助。
- XP/专有Coin、狗粮、漫画星芒和角色属于品牌图形，在对应页面需求明确后定制。当前不引入第二个开源主图标库，也不为暂未实现的食物生成商品清单。
- 图标和文字同时出现时图形对读屏隐藏；纯图标按钮必须有中文accessibilityLabel及44×44 pt以上热区，资源透明留白不算可见图形本身的可读性。

## SwiftUI接入前的验收要求

优先以Xcode Asset Catalog支持的静态矢量资源接入并验证最低iPadOS17。若采用PDF派生，保留原SVG、脚本和许可；不为了图标增加第三方运行时解析库。资源读取接口应有明确通用回退，不能失败后展示空白按钮。Light/Dark tint、普通/MAX、旧库任意图标标识及编辑保存不改tag都需专项验证。

002B网页样稿可直接嵌入同版SVG用于视觉比较；样稿用法不代表App原生资源已经接入。系统图标如在样稿中用文字按钮代替，应明确保留原动作而非仿造另一套图标。
