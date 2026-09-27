import Foundation

/// 从系统通知中心读取的只读请求快照。
///
/// `scheduledAt` 允许为空，因为未知触发器仍应被协调器识别并替换，不能静默当成正确请求。
nonisolated struct PendingNotificationRequestSnapshot: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let scheduledAt: Date?
}
