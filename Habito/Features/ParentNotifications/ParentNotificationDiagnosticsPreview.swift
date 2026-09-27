import SwiftData
import SwiftUI

#Preview("通知诊断 · 横屏", traits: .landscapeLeft) {
    ParentNotificationDiagnosticsPreview()
}

/// 使用内存数据和确定性系统边界展示诊断页，不读取预览设备的真实通知设置。
@MainActor
private struct ParentNotificationDiagnosticsPreview: View {
    private let container: ModelContainer?
    private let model: ParentNotificationDiagnosticsViewModel?

    init() {
        do {
            let container = try AppModelContainer.make(inMemory: true)
            self.container = container
            model = ParentNotificationDiagnosticsViewModel(
                service: NotificationPermissionService(
                    context: container.mainContext,
                    provider: PreviewNotificationPermissionProvider()
                )
            )
        } catch {
            container = nil
            model = nil
        }
    }

    var body: some View {
        NavigationStack {
            if let model {
                ParentNotificationDiagnosticsView(model: model)
            } else {
                ContentUnavailableView(
                    "notification.diagnosticsErrorTitle",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
        }
    }
}

@MainActor
private struct PreviewNotificationPermissionProvider: NotificationPermissionProviding {
    func diagnostics() async -> NotificationDiagnosticSnapshot {
        NotificationDiagnosticSnapshot(
            authorization: .authorized,
            alerts: .enabled,
            sounds: .disabled
        )
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        .authorized
    }
}
