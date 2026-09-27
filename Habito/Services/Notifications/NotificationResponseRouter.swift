import Observation

/// 跨越 UIKit 通知回调与 SwiftUI 根视图生命周期，保留最近一次点击意图。
@MainActor
@Observable
final class NotificationResponseRouter {
    private(set) var revision = 0
    private var pendingRequestIdentifier: String?

    /// 冷启动时根视图可能尚未创建，因此先保存 identifier，待根视图按 revision 消费。
    func receive(requestIdentifier: String) {
        pendingRequestIdentifier = requestIdentifier
        revision &+= 1
    }

    func consumePendingRequestIdentifier() -> String? {
        defer { pendingRequestIdentifier = nil }
        return pendingRequestIdentifier
    }
}
