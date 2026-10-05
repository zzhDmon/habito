#if DEBUG
    import Foundation
    import SwiftData

    /// 解析 UI 测试专用启动参数，并创建与正式数据完全隔离的磁盘容器。
    ///
    /// 只有 Debug 构建且显式传入 `--habito-ui-testing` 时才会启用。测试容器保留在 App
    /// 沙箱内，使测试可以终止并重新启动 App 来核对计时状态恢复；正式容器不会被读取或清理。
    struct UITestLaunchConfiguration {
        static let enableArgument = "--habito-ui-testing"
        static let resetArgument = "--habito-ui-reset"
        static let emptyDataArgument = "--habito-ui-empty"
        static let templateOnlyArgument = "--habito-ui-template-only"
        static let notificationRequestArgument = "--habito-ui-notification-request"
        static let delayedNotificationArgument = "--habito-ui-delayed-notification"
        static let notificationsDeniedArgument = "--habito-ui-notifications-denied"
        static let notificationsFailArgument = "--habito-ui-notifications-fail"
        static let systemReferenceEnvironmentKey = "HABITO_UI_SYSTEM_REFERENCE"

        let shouldReset: Bool
        let shouldSeedSampleData: Bool
        let shouldSeedTemplateOnly: Bool
        let notificationRequestIdentifier: String?
        /// 兼容旧参数名，但现在由测试确认首页后显式触发，不再用固定延时。
        let shouldPrepareNotificationResponse: Bool
        let shouldDenyNotifications: Bool
        let shouldFailNotificationScheduling: Bool

        static var current: UITestLaunchConfiguration? {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains(enableArgument) else { return nil }
            let notificationRequestIdentifier = arguments.firstIndex(of: notificationRequestArgument)
                .flatMap { index in
                    arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
                }
            return UITestLaunchConfiguration(
                shouldReset: arguments.contains(resetArgument),
                shouldSeedSampleData: !arguments.contains(emptyDataArgument),
                shouldSeedTemplateOnly: arguments.contains(templateOnlyArgument),
                notificationRequestIdentifier: notificationRequestIdentifier,
                shouldPrepareNotificationResponse: arguments.contains(delayedNotificationArgument),
                shouldDenyNotifications: arguments.contains(notificationsDeniedArgument),
                shouldFailNotificationScheduling: arguments.contains(notificationsFailArgument)
            )
        }

        /// 创建可跨 App 重启连续计时的 Debug 时钟；手动启动旧测试参数时仍使用系统时钟。
        ///
        /// - Parameter environment: 启动环境，可由单测传入，不修改进程全局环境。
        /// - Returns: 存在有效测试基准时返回映射时钟，否则返回手动探针兼容的系统时钟。
        /// - Throws: 显式传入的基准不是有限时间戳时拒绝，避免静默掩盖坏夹具。
        func makeDateProvider(environment: [String: String] = ProcessInfo.processInfo.environment) throws
            -> any DateProviding
        {
            guard let rawReference = environment[Self.systemReferenceEnvironmentKey] else {
                return SystemDateProvider()
            }
            guard let reference = TimeInterval(rawReference), reference.isFinite else {
                throw CocoaError(.coderInvalidValue)
            }
            return UITestDateProvider(
                referenceSystemDate: Date(timeIntervalSince1970: reference),
                referenceTestDate: try Date("2026-09-27T02:00:00Z", strategy: .iso8601)
            )
        }

        /// 创建 UI 测试独占的磁盘容器。
        ///
        /// - Returns: 使用独立 SQLite 文件的完整 Habito 模型容器。
        /// - Throws: Application Support 目录或 SwiftData 容器无法创建时抛出错误。
        func makeContainer() throws -> ModelContainer {
            let fileManager = FileManager.default
            let directory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let storeURL = directory.appendingPathComponent("HabitoUITests.store")
            return try AppModelContainer.make(storeURL: storeURL)
        }

        /// 创建与正式家长 PIN 完全隔离的 UI 测试 Keychain 存储。
        func makeCredentialStore() -> KeychainParentPINCredentialStore {
            KeychainParentPINCredentialStore(
                service: "com.zhangzehua.Habito.ui-tests.parent-pin",
                account: "habito.ui-tests.parent-pin"
            )
        }
    }
#endif
