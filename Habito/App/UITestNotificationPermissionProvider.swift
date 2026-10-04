#if DEBUG
    /// UI 自动化使用的确定性通知权限边界，避免系统弹窗打断业务流程验收。
    @MainActor
    final class UITestNotificationPermissionProvider:
        NotificationPermissionProviding, NotificationRequestScheduling
    {
        private let authorization: NotificationAuthorizationState
        private let failsScheduling: Bool
        private var pending: [String: PendingNotificationRequestSnapshot] = [:]

        init(deniesAuthorization: Bool = false, failsScheduling: Bool = false) {
            authorization = deniesAuthorization ? .denied : .authorized
            self.failsScheduling = failsScheduling
        }

        func diagnostics() async -> NotificationDiagnosticSnapshot {
            NotificationDiagnosticSnapshot(
                authorization: authorization,
                alerts: .enabled,
                sounds: .enabled
            )
        }

        func requestAuthorization() async throws -> NotificationAuthorizationState {
            authorization
        }

        func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
            Array(pending.values)
        }

        func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
            if failsScheduling { throw SchedulingFailure.unavailable }
            pending[request.identifier] = PendingNotificationRequestSnapshot(
                identifier: request.identifier, title: request.title, body: request.body,
                scheduledAt: request.scheduledAt
            )
        }

        func removePendingNotificationRequest(identifier: String) async throws {
            pending[identifier] = nil
        }

        func deliveredNotificationIdentifiers() async throws -> [String] { [] }

        func removeDeliveredNotificationRequest(identifier: String) async throws {}

        private enum SchedulingFailure: Error {
            case unavailable
        }
    }
#endif
