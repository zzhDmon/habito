import Foundation

/// 从系统通知中心读取的只读请求快照。
///
/// `scheduledAt` 允许为空：未知触发器或缺少固定日期上下文的旧请求仍应被协调器替换，
/// 不能用它在当前设备设置下看似匹配的时间证明绝对时刻正确。
nonisolated struct PendingNotificationRequestSnapshot: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let scheduledAt: Date?
}
