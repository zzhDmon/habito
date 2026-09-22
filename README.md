# Habito

面向小学低年级孩子的 iPad 学习与自律工作台。V0 使用 SwiftUI、SwiftData 和本地通知，采用单设备、本地优先方案。

## 开发基线

- Xcode 27.0 或更新稳定版
- Swift 6，严格并发检查
- iPadOS 17.0 最低部署版本
- iPad 横屏
- 不使用第三方依赖

完整环境记录见 `docs/Habito-环境基线.md`，当前任务和交接状态见 `docs/Habito-V0-执行看板.md`。

## 构建

```bash
xcodebuild \
  -project Habito.xcodeproj \
  -scheme Habito \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/HabitoDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 测试

先通过 `xcrun simctl list devices available` 选择一个可用 iPad 模拟器，再执行：

```bash
xcodebuild \
  -project Habito.xcodeproj \
  -scheme Habito \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/HabitoDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 格式检查

```bash
xcrun swift-format lint --strict --recursive Habito HabitoTests
```
