import OSLog
import UIKit
import UserNotifications

/// 接收应用生命周期和本地通知回调。
///
/// SwiftUI 暂时没有可替代 `UNUserNotificationCenterDelegate` 的原生场景 API，
/// 因此这里使用最小的 `UIApplicationDelegate` 桥接，并把业务排程留在通知服务中。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let notificationResponseRouter = NotificationResponseRouter()
    private var notificationRebuildTrigger: NotificationRebuildTrigger?
    private var hasPendingTimeChange = false
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

    /// 由组合根在场景出现时连接全局重建入口；提前到达的生命周期事件不会丢失。
    ///
    /// - Important: 注入本身不触发额外排程；仅把尚未处理的系统变化合并为一次重建。
    func connectNotificationRebuildTrigger(_ trigger: NotificationRebuildTrigger) {
        notificationRebuildTrigger = trigger
        if hasPendingTimeChange {
            hasPendingTimeChange = false
            trigger.requestRebuild()
        }
    }

    /// 系统在午夜、校时及夏令时变化时调用；挂起期间的事件由系统在回前台时交付。
    ///
    /// 这里只转发事件，不直接操作 SwiftData 或通知中心。服务按注入的日历/时区重算未来实例，
    /// 既有根视图结构化任务完成后刷新今日页面，已完成记录仍保留原绝对时间。
    func applicationSignificantTimeChange(_ application: UIApplication) {
        guard let notificationRebuildTrigger else {
            hasPendingTimeChange = true
            return
        }
        notificationRebuildTrigger.requestRebuild()
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
