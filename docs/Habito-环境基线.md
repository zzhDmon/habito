# Habito 开发与设备环境基线

> 最近探测：2026-09-22 22:00（Asia/Shanghai）。仅记录项目需要的信息，不记录设备序列号、UDID 等敏感标识。

## 已确认的开发机环境

| 项目 | 当前值 | 来源 |
|---|---|---|
| 设备 | MacBook Pro，Apple M5，32 GB 内存 | `system_profiler SPHardwareDataType` |
| 架构 | arm64 | `uname -m` |
| macOS | 26.6.2，Build 25G83 | `sw_vers` |
| Xcode | 27.0，Build 27A266a | `xcodebuild -version` |
| Swift | Apple Swift 6.4 | `xcrun swift --version` |
| iOS/iPadOS SDK | 27.0 | `xcodebuild -showsdks` |
| iOS Simulator SDK | 27.0 | `xcodebuild -showsdks` |
| 已安装 Simulator Runtime | iOS 17.2、iOS 27.0 | `xcrun simctl list runtimes`（沙箱外） |

## 目标 iPad

| 项目 | 当前值 | 状态 |
|---|---|---|
| 型号 | 2025 款 iPad（A16，iPad15,7） | M0-003 真机探针已确认 |
| iPadOS 版本 | iPadOS 26.6（Build 23G71） | M0-003 真机探针已确认 |
| 是否孩子专用 | 主要由孩子使用，家长可拿到设备配置 | `ASSUMPTION`；不做多用户切换 |
| 首发方向 | 横屏 | 已确认 |

真机已通过数据线连接并完成配对，开发者模式和开发者信任均已启用。Xcode 当前 Personal Team 可用于自动签名；Habito 已完成无警告真机构建和安装，并通过冷启动、终止后重启、横屏显示及前后台恢复验证。免费开发描述文件有效期至 2026-09-29 21:27（Asia/Shanghai）。

## 工具链风险

1. Xcode 27.0、Swift 6.4、iOS/iPadOS 27 SDK 与首次启动状态均已核验通过。
2. iOS 17.2 与 iOS 27.0 Simulator Runtime 均已安装，可分别回归最低部署版本与当前 SDK 行为；真机以 iPadOS 26.6 为准。
3. 沙箱内 `simctl` 无权访问 CoreSimulatorService，沙箱外执行正常。这是执行环境限制，不是 Xcode 故障。
4. 旧交接稿记录开发机为 MacBook Pro M1，本次系统探测为 MacBook Pro M5。后续以本基线的实时探测值为准；该差异不影响 V0 产品范围。

## 已选开发基线

- 真机目标：iPadOS 26。
- 最低部署版本：iPadOS 17，保留 SwiftUI + SwiftData 的直接使用条件。
- 首发界面：横屏设计和验收；V0 不承诺完整竖屏体验。
- 设备形态：单台 iPad、单个孩子、本地数据。
- 工具链：Xcode 27.0 已安装，许可协议、首次启动状态、Swift、SDK 与模拟器服务均已复核。
- Swift 语言模式：Swift 6，开启严格并发检查与 Main Actor 默认隔离。
- Bundle ID：开发期使用 `com.zhangzehua.Habito`，已在当前 Personal Team 下完成自动签名验证。
- 测试：创建 `HabitoTests`，单元测试优先使用 Swift Testing；V0 工程壳不创建 UI Test target。
- 本地数据：SwiftData 默认本地持久化；测试与 Preview 使用独立内存容器。

Apple 官方 Xcode 系统要求表显示，Xcode 27 支持 iPadOS 15–27 的部署目标和 iPadOS 17 及以上设备。最终可用 SDK 仍以许可协议确认后的本机 `xcodebuild -showsdks` 结果为准。

## 落地前检查结论

- 当前激活开发目录：`/Applications/Xcode.app/Contents/Developer`。
- 当前仅发现一个激活的 Xcode 安装：Xcode 27.0。
- 当前数据卷可用空间约 158 GiB，未发现明显磁盘空间阻塞。
- 结论：M0-001 的工具链与工程配置基线已满足；可创建应用壳。iPadOS 26/27 Simulator Runtime 缺失不阻塞 M0-002，但应在 UI 专属行为验收前补装。

## 工程壳验证

- Xcode 工程：`Habito.xcodeproj`
- App target：`Habito`
- 单元测试 target：`HabitoTests`
- 验证模拟器：iPad Pro 12.9 英寸（第 6 代），iOS 17.2，横屏；iPad Pro 13 英寸（M5），iOS 27.0
- 干净构建：通过，无编译警告
- Swift Testing：`AppModelContainerTests` 在 iOS 17.2 与 iOS 27.0 模拟器均通过
- 静态分析：通过
- 格式检查：`swift-format lint --strict` 通过，规则保存在根目录 `.swift-format`
- 运行验证：模拟器安装和启动成功；SwiftData 磁盘容器创建成功；本地化占位页正常显示
- 真机验证：iPad（A16）/iPadOS 26.6 签名安装、冷启动、终止后重启、横屏和前后台恢复均正常

## 延后复核项

以下项目不阻塞当前开发，按计划延后复核：

- 设备是否长期只给一个孩子使用：继续标为假设，最迟在 M5-005 家庭试用前确认。
- 免费签名的实际到期行为：由 M5-006 按真机首次安装日起观察。
