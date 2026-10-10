# Habito 功能、交互、UI与易用性审查

日期：2026-10-10。源码基线：`f2680a1`。任务：`REVIEW-UX-001`。

本轮按用户要求检查并记录优化点，未修改产品代码。依据为源码、已有验收记录与三张实际截图；没有重新跑整套测试，也没有把静态推断写成现场复现。采用已安装的 swiftui-pro 基线复核导航、状态归属、Dynamic Type、VoiceOver、Reduce Motion与界面职责。

## 四维结论

| 维度 | 结论 | 优先关注 |
|---|---|---|
| 功能 | 计时恢复、手动完成、审核、奖励与镜头生命周期已有实现和自动化证据；跨任务同时计时的产品政策尚需明确 | UX-C04 |
| 交互 | 完成确认、短时撤销、失败重试已具备；任务编辑离开时缺少草稿保护，完成操作的视觉优先级可提高 | UX-C01、UX-C02 |
| UI | 漫画视觉与原生组件已统一；无镜头状态的大块占位及大字长提示增加了滚动负担 | UX-C03 |
| 产品易用性 | 常用预设、可选项折叠、喂食价格与余额不足提示已具备；首次没有任务时，操作入口可更直接 | UX-C05 |

以下优先级表示优化顺序，不是发布缺陷等级。本轮没有足够证据新增P0/P1发布阻断；这也不代表完成了全应用穷尽检查或实机验收。

## UX-C01：离开任务编辑前保护未保存内容（优先）

- **性质：静态确认的交互缺口；未新跑UI复现。** 修改标题、提醒、星期或奖励后直接返回，再进入会重新从持久化加载；当前没有保存草稿或未保存确认。
- 证据：[TaskTemplateEditorView](../Habito/Features/ParentTaskTemplates/TaskTemplateEditorView.swift) 第17～100行只处理保存、生命周期操作与通知警告；[TaskTemplateEditorViewModel](../Habito/Features/ParentTaskTemplates/TaskTemplateEditorViewModel.swift) 第9～12行持有输入，第103～114行加载，第130～145行才保存；[ParentGateView](../Habito/Features/ParentGate/ParentGateView.swift) 第80～84、118～122行使用原生关闭/编辑导航，没有转交未保存离开意图。
- 影响：家长调整多项后误按返回，会丢失尚未保存的输入，增加重复操作。
- 建议前后行为：目前直接离开；建议仅有实际修改时提供“继续编辑／放弃修改”，保存成功后正常返回。变化比较应覆盖原始奖励输入、提醒时间和可选时间，不只比较标题；未修改页面不弹确认。
- 实现边界：统一处理返回与关闭；仅加 `.interactiveDismissDisabled` 无法保护导航返回或显式关闭。暂不扩为自动保存草稿，避免悄悄改变持久化语义。
- 验收：无修改直接退出；修改后取消离开保留输入；放弃后数据库不变；保存失败仍留在页面；保存成功不重复提示；普通/MAX下确认按钮可操作。

## UX-C02：让孩子看懂还差多久，并突出完成动作（优先）

- **性质：体验建议。** 当前显示“已专注”、累计时长、进度条与目标时长；孩子需要自行相减。运行时最大黄色按钮一直是暂停，“完成打卡／提交检查”排在“10分钟后提醒我”后，二者均为次级样式。
- 证据：[TaskSessionTimerPanel](../Habito/Features/TaskSession/TaskSessionTimerPanel.swift) 第20～42行；[TaskSessionControlsView](../Habito/Features/TaskSession/TaskSessionControlsView.swift) 第27～75行；本轮查看的普通横屏摄像头截图也直接展示该层级。
- 建议前后行为：保留累计时长，补充短句“还差X分钟”；达到目标后显示“目标完成，可以打卡”，提高完成/提交按钮的位置或强调程度，稍后提醒保持次级。
- **ASSUMPTION：** 具体主按钮层级与短句未由用户确认。目标时长仍是引导，不自动完成、不强制等到目标、不改变审核或奖励规则。
- 验收：目标前、正好达到、超过目标及暂停均正确；剩余不出现负数；等待审核没有再次提交入口；VoiceOver能读到状态，不逐秒强制播报；普通/MAX与Reduce Motion可用。

## UX-C03：镜头没有画面时减少占位（优先）

- **性质：截图和源码确认的布局负担，非内容截断缺陷。** 未开始、暂停、无设备与拒绝权限时仍保留180pt高黑色画面；MAX下状态长句分多行，任务操作需要更多滚动。
- 证据：[TaskCameraPanel](../Habito/Features/TaskSession/TaskCameraPanel.swift) 第15～49行；[TaskSessionLoadedView](../Habito/Features/TaskSession/TaskSessionLoadedView.swift) 第44～69行在单列布局时将镜头排在计时操作之前。普通/MAX截图见下方证据清单。
- 建议前后行为：实时运行时保留人物小窗；无画面时使用紧凑状态条或可展开占位，短句如“镜头不可用，仍可计时”。拒绝授权的设置、异常重试入口保留44pt操作面积。暂停提示明确“镜头已关闭”。
- **ASSUMPTION：** 折叠样式与短句待确认；不改变用户已确认的镜头启停范围。必须保留预览连接建立所需宿主，不能为缩小空窗破坏“先连接图层再启动会话”的系统边界。
- 验收：运行实时画面正常；暂停/后台/离开实际停机；拒绝、无硬件、故障仍有解释；设置返回和快速启停不留下旧画面；两系普通/MAX横屏可操作，真实iPad验证镜像与左右方向。

## UX-C04：明确切换任务时旧计时的状态（需先确认规则）

- **性质：源码推断的产品歧义，未执行双任务现场复现。** 离开执行页只停摄像头，计时按已确认规则继续；开始另一个任务的服务只检查该任务的活动会话，没有跨任务互斥。因此不同任务可能同时累计专注时长。
- 证据：[KidTaskSessionView](../Habito/Features/TaskSession/KidTaskSessionView.swift) 第88～90行；[TaskProgressService](../Habito/Data/TaskProgress/TaskProgressService.swift) 第17～49、68～83行；[TodayTaskQueryService](../Habito/Features/Today/TodayTaskQueryService.swift) 第294～313行已把进行中任务优先展示，现有首页并非完全没有进行中反馈。
- 影响：孩子返回首页开始另一项时，可能不清楚前一项是否仍在计时；并行时长是否合理取决于产品规则。
- 建议：在开始另一项前清楚说明旧任务仍运行，并提供明确选择；首页区分“正在计时”和“已暂停”，避免共用进行中状态造成误解。
- **ASSUMPTION：** 单任务专注还是允许并行尚未确认。不能擅自自动暂停旧任务，更不能改成离开页面就暂停；后者与现有计时恢复决策冲突。
- 验收：固定时钟覆盖A运行→返回→开始B，以及暂停/恢复/跨午夜/通知跳转；验证最终选定政策下每项时长与保存事务正确，摄像头仍只随当前页面运行。

## UX-C05：空任务页给家长一个直接的下一步（次优先）

- **性质：易用性建议。** 首页无任务时说明“家长安排任务后，会显示在这里”，但空态本身没有配置动作；当前家长入口在顶部工具栏。
- 证据：[KidTodayTaskContent](../Habito/Features/Today/KidTodayTaskContent.swift) 第21～26行；[RootView](../Habito/App/RootView.swift) 第112～120行；已查看的10月8日品牌首页截图作为历史视觉补充，当前结论以源码为准。
- 建议前后行为：在首次未配置任务时增加“请家长安排任务”按钮，进入现有PIN门控，再使用现有常用任务预设；显示简短设置进度，如“设置PIN→添加任务→检查提醒”。已有家庭的休息日/放假空态保持适合孩子的说明，不每次弹引导。
- **ASSUMPTION：** 首次引导内容与展示条件待确认；不能只凭“今天无任务”判断未配置，更不能跳过PIN或自动建立任务。
- 验收：首次无模板、已有模板但今天不重复、放假、全完成与加载失败互相区分；按钮不绕过家长门控；通知拒绝不阻断任务保存。

## 已具备的能力与专项复核

- 完成二次确认已在TaskSessionControlsView第79～103行；固定短时撤销栏已在TaskSessionLoadedView第74～82行，建议不重复建设。
- 常用任务预设、时间/外观/自定义星期折叠和校验失败展开已在[TaskTemplateEditorForm](../Habito/Features/ParentTaskTemplates/TaskTemplateEditorForm.swift) 第5～7、25～26、40～97、170～177行；固定保存栏和键盘结束输入已有实现。
- [PetFeedingControls](../Habito/Features/Pet/PetFeedingControls.swift) 第12～31行已明确费用、效果、收据、失败与金币不足原因；不是只有禁用按钮。
- PIN门控、审核队列、通知配置提示已有实现与历史软件验收；本轮没有充分证据要求重构这些模块。PIN本机重置属于已确认产品边界，不临时扩大为新的身份验证需求。
- swiftui-pro专项：当前关键路径已有类型化NavigationStack、MainActor可观察状态、语义按钮、错误反馈、Dynamic Type布局与Reduce Motion处理。本轮真实关注点为导航草稿保护、操作层级及大字信息负担。摄像头UIKit互操作用于系统预览图层，不能仅因使用UIKit就判为问题；已有AX回退的首页布局也不机械改为Lazy容器。

## 证据与验证边界

- 代码提交`f2680a1`软件验收：两系各714单测定义/1432执行，普通与MAX横屏专项各1UI，Release与严格质量检查通过，详见[前置镜头验收](Habito-前置镜头小窗验收.md)。这是该提交的已有证据，不是本轮新运行结果。
- 本轮实际查看：普通截图`/tmp/habito-camera-accepted27-attachments/CF8C0343-7F17-427A-9B7F-F43874C6637C.png`；MAX滚动位置截图`/tmp/habito-camera-max27-final-attachments/335DD975-BACF-48E7-B46E-D0C9AB8FE893.png`。它们是会话临时文件，长期交接以验收记录和源码结论为准。
- 历史视觉补充：[品牌首页](personalization/home-final-ios17.png)，不能替代本轮当前源UI回归。
- 本轮文档检查：相对链接文件存在、所引用关键源码位置核对、差异检查，且产品与测试源码没有新增修改。
- 仍待：真实人物预览、镜像/方向、相机使用指示、现场VoiceOver、真实通知送达与至少14天家庭观察。优化建议没有作为已经完成的功能验收。

建议按UX-C01→UX-C02→UX-C03实施；UX-C04先确认计时政策，UX-C05再补首次体验。每项独立任务、相关验证后独立本地提交，避免把多个产品决策合在一次变更里。
