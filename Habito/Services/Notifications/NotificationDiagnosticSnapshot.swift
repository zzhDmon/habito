import Foundation

/// 家长中心展示的系统通知能力快照。
nonisolated struct NotificationDiagnosticSnapshot: Equatable, Sendable {
    let authorization: NotificationAuthorizationState
    let alerts: NotificationDeliverySettingState
    let sounds: NotificationDeliverySettingState

    /// 只有授权与提醒展示均可用时，界面才能声称系统会显示提醒。
    var canPresentAlerts: Bool {
        authorization.canSchedule && alerts == .enabled
    }

    /// 声音是独立开关，不能由总授权状态推断。
    var canPlaySounds: Bool {
        canPresentAlerts && sounds == .enabled
    }
}
