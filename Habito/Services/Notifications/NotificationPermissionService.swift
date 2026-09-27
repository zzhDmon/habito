import Foundation
import SwiftData

/// 协调系统权限读取，并持久化最近一次授权状态供诊断追踪。
@MainActor
struct NotificationPermissionService {
    private let context: ModelContext
    private let provider: any NotificationPermissionProviding

    init(context: ModelContext, provider: any NotificationPermissionProviding) {
        self.context = context
        self.provider = provider
    }

    /// 读取最新系统设置并记录总授权状态。
    func refresh() async throws -> NotificationDiagnosticSnapshot {
        let snapshot = await provider.diagnostics()
        try persist(snapshot.authorization)
        return snapshot
    }

    /// 仅在系统尚未决定时请求权限，然后重新读取各单项设置。
    ///
    /// 拒绝权限是正常结果而不是错误；只有系统调用或持久化失败才抛出。
    func requestIfNeeded() async throws -> NotificationDiagnosticSnapshot {
        let current = await provider.diagnostics()
        if current.authorization == .notDetermined {
            _ = try await provider.requestAuthorization()
        }
        return try await refresh()
    }

    private func persist(_ authorization: NotificationAuthorizationState) throws {
        do {
            let key = AppSettings.defaultKey
            let descriptor = FetchDescriptor<AppSettings>(
                predicate: #Predicate { $0.singletonKey == key }
            )
            let settings: AppSettings
            if let existing = try context.fetch(descriptor).first {
                settings = existing
            } else {
                settings = AppSettings()
                context.insert(settings)
            }
            settings.recordNotificationAuthorization(authorization)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
