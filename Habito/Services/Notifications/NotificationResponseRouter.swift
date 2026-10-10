import Observation

/// 跨越 UIKit 通知回调与 SwiftUI 根视图生命周期，保留最近一次点击意图。
@MainActor
@Observable
final class NotificationResponseRouter {
    private(set) var revision = 0
    private var pendingRequestIdentifier: String?

    #if DEBUG
        private(set) var preparedUITestRequestIdentifier: String?

        /// UI 测试在确认首页可见后显式触发，不用固定延时猜测 Accessibility 何时就绪。
        func prepareUITestResponse(requestIdentifier: String) {
            preparedUITestRequestIdentifier = requestIdentifier
        }

        func deliverPreparedUITestResponse() {
            guard let identifier = preparedUITestRequestIdentifier else { return }
            preparedUITestRequestIdentifier = nil
            receive(requestIdentifier: identifier)
        }
    #endif

    /// 冷启动时根视图可能尚未创建，因此先保存 identifier，待根视图按 revision 消费。
    func receive(requestIdentifier: String) {
        pendingRequestIdentifier = requestIdentifier
        revision &+= 1
    }

    /// 页面有未保存输入或正在提交时保留点击意图；解除保护后仍只消费一次。
    func consumePendingRequestIdentifier(isNavigationProtected: Bool = false) -> String? {
        guard !isNavigationProtected else { return nil }
        defer { pendingRequestIdentifier = nil }
        return pendingRequestIdentifier
    }
}
