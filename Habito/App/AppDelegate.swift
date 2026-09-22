import OSLog
import UIKit
import UserNotifications

/// 接收应用生命周期和本地通知回调。
///
/// SwiftUI 暂时没有可替代 `UNUserNotificationCenterDelegate` 的原生场景 API，
/// 因此这里使用最小的 `UIApplicationDelegate` 桥接，并把业务排程留在通知服务中。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let logger = Logger(
        subsystem: "com.zhangzehua.Habito",
        category: "LocalNotification"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// App 位于前台时仍展示探针通知，便于 M0-004 验证前台场景。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        logger.info("前台收到本地通知：\(notification.request.identifier, privacy: .public)")
        return [.banner, .list, .sound]
    }

    /// 记录用户点击通知的事实；V0 的正式页面路由将在 M4-006 接入。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        logger.info("用户点击本地通知：\(response.notification.request.identifier, privacy: .public)")
    }
}
