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
        static let notificationRequestArgument = "--habito-ui-notification-request"
        static let delayedNotificationArgument = "--habito-ui-delayed-notification"
        static let notificationsDeniedArgument = "--habito-ui-notifications-denied"
        static let notificationsFailArgument = "--habito-ui-notifications-fail"

        let shouldReset: Bool
        let shouldSeedSampleData: Bool
        let notificationRequestIdentifier: String?
        let shouldDelayNotificationResponse: Bool
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
                notificationRequestIdentifier: notificationRequestIdentifier,
                shouldDelayNotificationResponse: arguments.contains(delayedNotificationArgument),
                shouldDenyNotifications: arguments.contains(notificationsDeniedArgument),
                shouldFailNotificationScheduling: arguments.contains(notificationsFailArgument)
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
