import Observation
import OSLog

/// 刷新系统通知设置，并把不可用状态原样交给页面展示。
@MainActor
@Observable
final class ParentNotificationDiagnosticsViewModel {
    private(set) var state: ParentNotificationDiagnosticsState = .loading
    private let service: NotificationPermissionService
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "NotificationDiagnostics")

    init(service: NotificationPermissionService) {
        self.service = service
    }

    func refresh() async {
        do {
            state = .loaded(try await service.refresh())
        } catch {
            logger.error("通知诊断刷新失败：\(String(describing: type(of: error)), privacy: .public)")
            state = .failed
        }
    }
}
