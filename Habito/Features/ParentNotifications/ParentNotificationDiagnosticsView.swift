import SwiftUI
import UIKit

/// 展示系统总授权、提醒样式和声音三个独立状态，并提供系统设置入口。
struct ParentNotificationDiagnosticsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ParentNotificationDiagnosticsViewModel

    init(model: ParentNotificationDiagnosticsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("notification.diagnosticsLoading")
            case let .loaded(snapshot):
                Form {
                    Section("notification.diagnosticsStatusSection") {
                        statusRow(
                            "notification.diagnosticsAuthorization",
                            value: authorizationTitle(snapshot.authorization),
                            isAvailable: snapshot.authorization.canSchedule
                        )
                        statusRow(
                            "notification.diagnosticsAlerts",
                            value: deliveryTitle(snapshot.alerts),
                            isAvailable: snapshot.canPresentAlerts
                        )
                        statusRow(
                            "notification.diagnosticsSounds",
                            value: deliveryTitle(snapshot.sounds),
                            isAvailable: snapshot.canPlaySounds
                        )
                    }

                    NotificationSchedulingStatusView(state: model.schedulingState, onRetry: model.retryScheduling)

                    Section {
                        Button("notification.openSettings", systemImage: "gear", action: openSettings)
                    } footer: {
                        Text("notification.diagnosticsFooter")
                    }
                }
            case .failed:
                ContentUnavailableView {
                    Label("notification.diagnosticsErrorTitle", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text("notification.diagnosticsErrorMessage")
                } actions: {
                    Button("notification.diagnosticsRetry") {
                        Task { await model.refresh() }
                    }
                }
            }
        }
        .navigationTitle("notification.diagnosticsTitle")
        .accessibilityIdentifier(HabitoAccessibilityID.parentNotificationDiagnostics)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
    }

    private func statusRow(
        _ label: LocalizedStringKey,
        value: LocalizedStringKey,
        isAvailable: Bool
    ) -> some View {
        LabeledContent {
            Label(value, systemImage: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isAvailable ? .green : .secondary)
        } label: {
            Text(label)
        }
    }

    private func authorizationTitle(_ state: NotificationAuthorizationState) -> LocalizedStringKey {
        switch state {
        case .notDetermined: "notification.authorization.notDetermined"
        case .denied: "notification.authorization.denied"
        case .authorized: "notification.authorization.authorized"
        case .provisional: "notification.authorization.provisional"
        case .ephemeral: "notification.authorization.ephemeral"
        case .unknown: "notification.authorization.unknown"
        }
    }

    private func deliveryTitle(_ state: NotificationDeliverySettingState) -> LocalizedStringKey {
        switch state {
        case .enabled: "notification.delivery.enabled"
        case .disabled: "notification.delivery.disabled"
        case .notSupported: "notification.delivery.notSupported"
        case .unknown: "notification.delivery.unknown"
        }
    }

    private func openSettings() {
        // UIApplication 只用于 Apple 提供的应用设置深链；页面仍由 SwiftUI 管理生命周期。
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
