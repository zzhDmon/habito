import Foundation
@testable import Habito

/// 通知 ViewModel 测试替身，不访问系统权限或真实通知队列。
final class FakeLocalNotificationService: LocalNotificationScheduling {
    var currentAuthorizationState: NotificationAuthorizationState = .notDetermined
    var requestedAuthorizationState: NotificationAuthorizationState = .authorized
    var alertSetting: NotificationDeliverySettingState = .enabled
    var soundSetting: NotificationDeliverySettingState = .enabled
    var requestCount = 0
    var requestError: (any Error)?
    var onRequestAuthorization: (() async throws -> Void)?
    var pendingDate: Date?
    var scheduledDate = Date(timeIntervalSince1970: 2_000_000_000)
    var scheduledScenario: NotificationProbeScenario?
    var scheduledDelay: TimeInterval?
    var didCancel = false

    func diagnostics() async -> NotificationDiagnosticSnapshot {
        NotificationDiagnosticSnapshot(
            authorization: currentAuthorizationState,
            alerts: alertSetting,
            sounds: soundSetting
        )
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        requestCount += 1
        if let requestError { throw requestError }
        if let onRequestAuthorization {
            self.onRequestAuthorization = nil
            try await onRequestAuthorization()
        }
        currentAuthorizationState = requestedAuthorizationState
        return requestedAuthorizationState
    }

    func scheduleProbe(
        for scenario: NotificationProbeScenario,
        after delay: TimeInterval
    ) async throws -> Date {
        scheduledScenario = scenario
        scheduledDelay = delay
        pendingDate = scheduledDate
        return scheduledDate
    }

    func pendingProbeDate() async -> Date? {
        pendingDate
    }

    func cancelProbe() {
        didCancel = true
        pendingDate = nil
    }
}
