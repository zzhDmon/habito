import Foundation

/// 正式业务与通知探针共享的最小权限和诊断系统边界。
@MainActor
protocol NotificationPermissionProviding {
    func diagnostics() async -> NotificationDiagnosticSnapshot
    func requestAuthorization() async throws -> NotificationAuthorizationState
}
