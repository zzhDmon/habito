import SwiftData
import SwiftUI

#Preview("通知诊断 · 横屏", traits: .landscapeLeft) {
    ParentNotificationDiagnosticsPreview()
}

#Preview("通知诊断 · 大字号", traits: .landscapeLeft) {
    ParentNotificationDiagnosticsPreview()
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// 使用内存数据和确定性系统边界展示诊断页，不读取预览设备的真实通知设置。
@MainActor
private struct ParentNotificationDiagnosticsPreview: View {
    private let container: ModelContainer?
    private let model: ParentNotificationDiagnosticsViewModel?

    init() {
        do {
            let container = try AppModelContainer.make(inMemory: true)
            let trigger = NotificationRebuildTrigger()
            // 预览只注入值快照，不创建系统请求，也不写入正式持久化容器。
            trigger.record(
                NotificationRebuildResult(
                    selection: NotificationCandidateSelection(
                        primaryCandidates: [],
                        coverageThrough: try LocalDate(dateKey: "2026-10-18"),
                        isCoverageBoundaryPartial: false,
                        hasMinimumCoverage: true
                    ),
                    reconciliation: NotificationReconciliationReport(),
                    authorization: .authorized,
                    scheduledSnoozeCount: 0
                ),
                checkedAt: Date(timeIntervalSince1970: 1_791_100_000)
            )
            self.container = container
            model = ParentNotificationDiagnosticsViewModel(
                service: NotificationPermissionService(
                    context: container.mainContext,
                    provider: PreviewNotificationPermissionProvider()
                ),
                rebuildTrigger: trigger
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
