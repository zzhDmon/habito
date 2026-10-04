/// 正式任务通知使用的窄系统边界。
///
/// 协调器通过该协议读取、添加和逐条移除请求；逐条操作使一个失败不会中断其他正确请求。
@MainActor
protocol NotificationRequestScheduling {
    func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot]

    func addNotificationRequest(_ request: TaskNotificationRequest) async throws

    func removePendingNotificationRequest(identifier: String) async throws

    /// 已送达通知是另一份系统集合，取消挂起请求不会清掉通知中心中的旧卡片。
    func deliveredNotificationIdentifiers() async throws -> [String]

    func removeDeliveredNotificationRequest(identifier: String) async throws
}
