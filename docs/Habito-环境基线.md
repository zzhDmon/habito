# Habito 开发与设备环境基线

> 最近探测：2026-09-22 17:59（Asia/Shanghai）。仅记录项目需要的信息，不记录设备序列号、UDID 等敏感标识。

## 已确认的开发机环境

| 项目 | 当前值 | 来源 |
|---|---|---|
| 设备 | MacBook Pro，Apple M5，32 GB 内存 | `system_profiler SPHardwareDataType` |
| 架构 | arm64 | `uname -m` |
| macOS | 26.6.2，Build 25G83 | `sw_vers` |
| Xcode | 15.2，Build 15C500b | `xcodebuild -version` |
| Swift | Apple Swift 5.9.2 | `xcrun swift --version` |
| iOS/iPadOS SDK | 17.2 | `xcodebuild -showsdks` |
| iOS Simulator SDK | 17.2 | `xcodebuild -showsdks` |

## 目标 iPad

| 项目 | 当前值 | 状态 |
|---|---|---|
| 型号 | 2025 年款，具体产品线/型号未知 | 不阻塞开发；延后到 M0-003 真机探针确认 |
| iPadOS 版本 | 目标按 iPadOS 26 | `ASSUMPTION`；真机可升级，M0-003 复核 |
| 是否孩子专用 | 主要由孩子使用，家长可拿到设备配置 | `ASSUMPTION`；不做多用户切换 |
| 首发方向 | 横屏 | 已确认 |

探测时 `xcrun xctrace list devices` 与 `xcrun devicectl list devices` 均未发现可用真机。

## 工具链风险

1. 当前 Xcode 仅包含 iOS/iPadOS 17.2 SDK；目标 iPad 版本确认后，必须核对该 Xcode 是否支持连接、构建和调试。
2. `xcrun simctl list runtimes` 当前无法连接 CoreSimulatorService。错误可能来自旧工具链与当前 macOS 的兼容性，也可能与当前受限执行环境有关，尚未定因。
3. 在 `M0-001` 前需要在正常桌面会话中启动 Xcode，确认是否可创建/启动 iPad 模拟器；若仍失败，再决定升级 Xcode 或修复模拟器服务。
4. 旧交接稿记录开发机为 MacBook Pro M1，本次系统探测为 MacBook Pro M5。后续以本基线的实时探测值为准；该差异不影响 V0 产品范围。

## 已选开发基线

- 真机目标：iPadOS 26。
- 最低部署版本：iPadOS 17，保留 SwiftUI + SwiftData 的直接使用条件。
- 首发界面：横屏设计和验收；V0 不承诺完整竖屏体验。
- 设备形态：单台 iPad、单个孩子、本地数据。
- 工具链：正式创建工程前将 Xcode 15.2 升级至支持 iPadOS 26 SDK 的稳定版本；优先选择 Xcode 26.6，与当前 macOS 26.6.2 和 iPadOS 26 目标匹配。安装后重新记录 Xcode、Swift、SDK 与模拟器状态。

Apple 官方 Xcode 系统要求表显示，Xcode 26 系列包含 iOS/iPadOS 26 SDK，并支持 iPadOS 15 及以上设备；当前 Xcode 15.2 只有 iOS 17.2 SDK，不能作为 iPadOS 26 的正式开发基线。

## 延后复核项

以下项目不再阻塞 D-001，在 M0-003 连接真机时复核：

- 目标 iPad 的具体型号/产品线。
- 实际 iPadOS 小版本。
- 设备是否长期只给一个孩子使用。
