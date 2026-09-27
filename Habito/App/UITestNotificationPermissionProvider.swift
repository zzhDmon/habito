#if DEBUG
    /// UI 自动化使用的确定性通知权限边界，避免系统弹窗打断业务流程验收。
    @MainActor
    struct UITestNotificationPermissionProvider:
        NotificationPermissionProviding, NotificationRequestScheduling
    {
        func diagnostics() async -> NotificationDiagnosticSnapshot {
            NotificationDiagnosticSnapshot(
                authorization: .authorized,
                alerts: .enabled,
                sounds: .enabled
            )
        }

        func requestAuthorization() async throws -> NotificationAuthorizationState {
            .authorized
        }

        func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
            []
        }

        func addNotificationRequest(_ request: TaskNotificationRequest) async throws {}

        func removePendingNotificationRequest(identifier: String) async throws {}
    }
#endif
