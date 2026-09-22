import Foundation
@testable import Habito

/// 通知 ViewModel 测试替身，不访问系统权限或真实通知队列。
final class FakeLocalNotificationService: LocalNotificationScheduling {
    var currentAuthorizationState: NotificationAuthorizationState = .notDetermined
    var requestedAuthorizationState: NotificationAuthorizationState = .authorized
    var pendingDate: Date?
    var scheduledDate = Date(timeIntervalSince1970: 2_000_000_000)
    var scheduledScenario: NotificationProbeScenario?
    var scheduledDelay: TimeInterval?
    var didCancel = false

    func authorizationState() async -> NotificationAuthorizationState {
        currentAuthorizationState
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
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
