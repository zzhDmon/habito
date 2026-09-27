/// 正式任务通知使用的窄系统边界。
///
/// 协调器通过该协议读取、添加和逐条移除请求；逐条操作使一个失败不会中断其他正确请求。
@MainActor
protocol NotificationRequestScheduling {
    func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot]

    func addNotificationRequest(_ request: TaskNotificationRequest) async throws

    func removePendingNotificationRequest(identifier: String) async throws
}
