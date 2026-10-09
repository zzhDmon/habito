# 单任务确认与礼花反馈验收

日期：2026-10-08。任务：FEEDBACK-001。总进度仍为6/7，原目标真机与14天家庭观察未完成。

## 行为

- 点击“完成打卡”或“提交给家长”先询问“真的已经完成了吗？”。“还没完成”不调用业务用例，不产生完成、提交或奖励；取消后退出重开仍可操作。
- “确认完成”才调用原完成事务，时间仍取确认时刻。保存成功的真实收据触发小狗、鼓励文字、真实金额及一次1.4秒礼花。零奖励仍庆祝努力。
- 审核任务提示“完成了，交给家长”，正文说明通过后领奖。提交成功只显示已提交和等待；家长审核后的真实收据继续复用庆祝组件。
- 礼花不接收点击，也不进入VoiceOver朗读；不开常驻计时器、不延长5秒撤销。减少动态效果直接用静态星光；动态分支默认透明终帧，避免切换系统设置后残留纸屑。

## 验证范围

- 两系基础包：`/tmp/habito-completionconfirm-final-17.xcresult`、`/tmp/habito-completionconfirm-final-27.xcresult`。各689定义/1392执行完整单测及4条UI通过，零失败/跳过。17为普通字号/浅色，27为真实最大辅助字号/深色。
- 四条UI：自行确认取消及重开、审核提交取消及重开、真实奖励只反馈一次且撤销可达、零奖励自主完成。既有UI测试中的全部完成/提交动作均已适配确认步骤；本卡未重跑无关完整UI套件。
- 单测包含保存失败无收据、重复完成与审核等待不发奖、真实金额、减少动态效果首帧及最大字号原生渲染。
- 基础包通过后，仅调整礼花纸屑的纵向轨迹和渐隐曲线。最终源补验：两系`/tmp/habito-completionconfetti-polish-{17,27}.xcresult`，各7定义/26执行反馈单测及1条真实奖励/撤销UI。最终通过状态见机器记录。
- 最终Release构建通过（`/tmp/habito-feedback-release-final.log`的build动作）；Debug静态分析通过（`/tmp/habito-feedback-analyze.log`）。全仓swift-format严格检查零输出、工程解析及diff检查通过。
- 原Localizable的467键翻译语义与HEAD一致；保留已有格式/提取元数据差异。个性化头像、名称及用户已有改动未覆盖；本轮未提交或推送。

## 发现与修复

- 初版动画捕获GeometryProxy产生Sendable警告：改为捕获CGSize值，粒子数量令牌明确nonisolated不可变。最终无Swift/严格并发告警；Xcode未使用AppIntents的元数据提示和已记录的R-009方向提示仍为环境提示。
- 27原生Alert把同一按钮暴露成嵌套父子AX节点，原四条UI无法唯一定位（原失败报告`/tmp/habito-completionconfirm-27.xcresult`保留）。修订为限定当前Alert内相同标识的firstMatch后，四条全部通过，保留实际保存/取消/金额断言。
- 最初将Release build与analyze连用，analyze读取@testable测试模块时因Release未开启enable-testing失败；保留原日志。正式Release build成功，随后按项目既有Debug配置静态分析成功，未放宽产品设置。
- 27测试结束后可选simctl诊断等待600秒，精准停止对应diagnose进程；不停止测试或应用。失败包保持退出65，通过包保持退出0。
- swiftui-pro专项复核：确认状态仅View局部持有，业务写入仍在原用例；固定收据ID控制一次性生命周期；动态效果可降级、装饰不抢交互、系统弹窗适配大字；未新增第三方或UIKit依赖。

## 实际画面

[完成前确认](completion-feedback/confirmation-ios17.png) · [礼花动画帧](completion-feedback/confetti-ios17.png)。截图直接来自隔离模拟器，奖励11XP/10金币为原有合成测试夹具，不代表调整了正式奖励预设。

系统Reduce Motion开关与VoiceOver真实读屏、目标iPad手势表现继续属于原实机验收；本卡验证了静态分支与原生渲染，不将程序化验证冒充系统开关实测。
