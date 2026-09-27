import Foundation

/// 本地通知系统边界。
///
/// ViewModel 只依赖这个窄接口，因此单元测试不需要真的请求系统权限或等待两分钟。
@MainActor
protocol LocalNotificationScheduling: NotificationPermissionProviding {
    /// 安排一条指定延迟的探针通知。
    ///
    /// - Parameters:
    ///   - scenario: 当前手工验收场景，用于生成可辨识的通知文案。
    ///   - delay: 从当前时刻起的延迟秒数。
    /// - Returns: 预计触发时间。
    /// - Throws: 延迟无效或系统拒绝添加通知请求时抛出错误。
    func scheduleProbe(
        for scenario: NotificationProbeScenario,
        after delay: TimeInterval
    ) async throws -> Date

    /// 返回仍在系统队列中的探针触发时间。
    func pendingProbeDate() async -> Date?

    /// 取消尚未触发的探针通知。
    func cancelProbe()
}
