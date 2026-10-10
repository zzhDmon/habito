# 前置镜头小窗验收（CAMERA-001）

## 确认范围

2026-10-10 用户要求任务开始计时时留一个前置摄像头小窗口，并确认：仅任务运行且 App 在前台时开启，暂停、完成、等待审核、后台或离开页面关闭；仅本机实时镜像预览，不录制、不上传、不请求麦克风。权限失败和设备不可用不改变任务计时/完成规则。

## 实现与边界

- `RootView` 通过任务页面工厂注入独立相机状态；状态位于 MainActor，采集会话配置/启停位于 `FrontCameraService` actor，阻塞式系统调用不占用 UI 主线程。
- 页面只合成运行/完成/审核/场景事实并转发意图，递增世代防止旧授权返回重新开启镜头，旧停机请求也不能关闭新会话。关闭意图立即撤下画面，actor 随后停止采集。
- 小窗位于任务说明下方，复用漫画面板。视频区域紧凑，状态文字在画面外随 Dynamic Type 换行。拒绝权限可打开应用设置，启动错误/中断可重试，系统中断解除只恢复仍有效的前台意图。
- Apple 的实时预览需要 `AVCaptureVideoPreviewLayer`；以最小 `UIViewRepresentable` 桥承载图层，主线程仅连接/解绑预览和按当前 UIWindowScene 方向更新镜像/旋转。最低版本仍为 iPadOS 17。
- `FrontCameraPreviewSource` 是不可变 `@unchecked Sendable` 系统桥：配置/启停入口强制接收 `isolated FrontCameraService`，UI 连接入口限定 MainActor；不跨 actor 传递视频帧。测试探针的 unchecked 由 NSLock 保护记录。未关闭严格并发检查。
- 新增 12 个本地化键与 Debug/Release 相机用途说明；没有照片/电影/音频输出、存储和网络写入，也没有修改数据库、账本或通知。

## 验证证据（软件验收通过）

| 门槛 | iPadOS 17.2 | iPadOS 27.0 |
|---|---|---|
| 最终完整单测 | 714 定义 / 1432 执行，0失败/跳过 | 714 定义 / 1432 执行，0失败/跳过 |
| 普通横屏实际 UI | 开始→暂停→继续→完成，镜头不可用不阻塞，通过 | 相同流程通过 |
| 最终 MAX 实际 UI | 最大辅助字号/light，相同流程通过 | 最大辅助字号/dark，相同流程通过 |
| 最终 MAX 包附带单测 | 12定义/26执行（相机9＋日期世代3） | 43定义/70执行（相机9＋通知重建34） |

- 干净完整包：`/tmp/habito-camera-full-final17.xcresult`、`/tmp/habito-camera-full-final27.xcresult`，exit0；原生摘要分别保存在同名前缀的 `-summary.json`。没有运行警告。
- 普通 UI：`/tmp/habito-camera-accepted17.xcresult`（相关9单测＋1UI）、`/tmp/habito-camera-accepted27.xcresult`（相关43单测＋1UI）。最终预览图层保留修订由下面最终 MAX 及完整单测覆盖。
- 最终源 MAX：`/tmp/habito-camera-max17-final.xcresult`、`/tmp/habito-camera-max27-final.xcresult`，exit0，各1条真实 UI。两系 `-final-settings.log` 记录实际 MAX 设置及恢复 `large/light`。
- 相机9个新测试定义涵盖权限拒绝/受限、不可用/失败、授权期间关闭、旧停机世代、取消授权等待、快速启停、后台/中断恢复、完成/审核保护与8种普通/MAX渲染参数；原 TaskSession 状态套件在完整门继续通过。
- 最终 Release：`/tmp/habito-camera-release-accepted.log`，exit0；最终 Debug 两系测试构建也通过。没有 Swift 编译或严格并发警告；现有工具提示仅 AppIntents 元数据跳过。27 UI 的横屏/full-screen 未来兼容提示沿用已记录 R-009，不扩大首发方向。
- Swift严格格式（17个生产/测试文件）、工程plist、本地化JSON、生成Info.plist相机用途说明、git diff --check及源指纹核对通过；未关闭并发检查，未引入第三方依赖。
- `swiftui-pro` 专项复核真实修正：大字号文字移到固定视频区外；窗口可读标签与父容器独立分组，避免标识向子元素传播；系统通知回调转交 MainActor；系统依赖从组合根注入；先连接预览再采集，启停不反复重建预览宿主；最低部署仍为17。
- 最终生产/测试/工程/本地化源指纹：`dc1f825fed0cd3937e19ef39af4af2c88d40f15390c151e8c9a8c51ec117393a`，清单 `/tmp/habito-camera-final-source.json`。
- 普通截图：`/tmp/habito-camera-accepted27-attachments/`；最终MAX截图：`/tmp/habito-camera-max27-final-attachments/`。已实际查看普通布局和MAX状态文字/按钮，未发现裁切问题。

### 过程失败与补验边界

- 首轮相关30定义通过，见 `/tmp/habito-camera-unit27.xcresult`，不代替最终源证据。
- 初始两系UI未发现纯装饰窗口；补标签后仍被父面板标识覆盖。通过 `/tmp/habito-camera-diagnostic17.xcresult` 的真实AX层级确认并修复父容器分组，普通两系复验通过。
- 初始失败测试卡在Xcode外围诊断，停止两个旧进程时影响了后续整包各一条单测（signal term）；`verified17/27` 原包因此各713通过/2失败（含UI），不当完整通过。已由最终全714干净包替换，不用拼接旧证据冒称整包成功。
- 初次MAX把非交互视频窗口套用按钮isHittable检查，系统在MAX时没有有效激活点。仅窗口检查改为完整可见范围；真实操作按钮仍保留可见范围与点击检查，最终MAX两系通过。初始尝试 `/tmp/habito-camera-max17/27.xcresult` 保留。
- 首次MAX设置时模拟器已关机，设置失败、没有运行测试；启动设备后执行真实MAX并在finally恢复。没有清空设备或应用数据库。

## 目标 iPad 现场清单

模拟器没有真实前置镜头，自动化仅证明无设备时 UI、启停状态和计时闭环，不代表人物画面验收。现场需检查：

1. 首次开始计时，允许相机权限，确认实时人物镜像和横屏左右两个方向均正立。
2. 暂停/完成/提交审核/返回首页后，确认窗口撤下实时画面且系统相机使用指示消失；后台、锁屏也停止。
3. 运行中返回前台或重新进入任务后恢复；暂停任务返回前台不打开镜头。
4. 拒绝权限后计时仍能完成；打开设置允许相机后，回到运行任务恢复预览。
5. VoiceOver 能读出窗口和状态；大字号下状态文字、重试和设置按钮可见并可操作。

实现验收时没有提交或推送；2026-10-10 用户另行授权按功能节奏本地提交。没有删除真实家庭数据或迁移正式数据库，未获推送授权。
