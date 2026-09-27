/// 家长通知诊断页的加载状态。
enum ParentNotificationDiagnosticsState: Equatable {
    case loading
    case loaded(NotificationDiagnosticSnapshot)
    case failed
}
