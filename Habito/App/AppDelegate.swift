import OSLog
import UIKit
import UserNotifications

/// 接收应用生命周期和本地通知回调。
///
/// SwiftUI 暂时没有可替代 `UNUserNotificationCenterDelegate` 的原生场景 API，
/// 因此这里使用最小的 `UIApplicationDelegate` 桥接，并把业务排程留在通知服务中。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let notificationResponseRouter = NotificationResponseRouter()
    private let logger = Logger(
        subsystem: "com.zhangzehua.Habito",
        category: "LocalNotification"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
            // UI 自动化用与系统回调相同的桥模拟“根视图显示前已点击通知”的冷启动顺序。
            if let configuration = UITestLaunchConfiguration.current,
                let identifier = configuration.notificationRequestIdentifier
            {
                if configuration.shouldPrepareNotificationResponse {
                    notificationResponseRouter.prepareUITestResponse(requestIdentifier: identifier)
                } else {
                    notificationResponseRouter.receive(requestIdentifier: identifier)
                }
            }
        #endif
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

    /// 把点击交给可跨冷启动保存意图的桥；页面解析仍由 SwiftData 业务服务负责。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        logger.info("用户点击本地通知：\(identifier, privacy: .public)")
        notificationResponseRouter.receive(requestIdentifier: identifier)
    }
}
