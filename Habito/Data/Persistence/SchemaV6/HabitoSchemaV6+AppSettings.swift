import Foundation
import SwiftData

// 冻结自 8e98ca7 的结构 7.0.0；历史字段、默认与关系不能随活跃模型演进。
extension HabitoSchemaV6 {
    /// 单设备应用设置与后台任务检查点。
    ///
    /// - Important: 此模型绝不保存 PIN 明文、摘要或盐。`parentPINCredentialKey`
    ///   只是 Keychain 条目的非敏感查找键，实际凭据由 M3-001 的 Keychain 服务管理。
    @Model
    final class AppSettings {
        static let defaultKey = "habito.default"
        static let parentPINKeychainAccount = "habito.parent-pin"

        @Attribute(.unique) private(set) var singletonKey: String
        var isOnboardingCompleted: Bool
        private(set) var parentPINCredentialKey: String?
        var lastInstanceGenerationAt: Date?
        var lastNotificationSchedulingAt: Date?
        var schedulingHorizonDateKey: String?
        var lastNotificationAuthorizationRawValue: String?
        var schemaVersion: Int

        init(
            singletonKey: String = AppSettings.defaultKey,
            isOnboardingCompleted: Bool = false,
            hasParentPIN: Bool = false,
            lastInstanceGenerationAt: Date? = nil,
            lastNotificationSchedulingAt: Date? = nil,
            schedulingHorizonDateKey: String? = nil,
            lastNotificationAuthorization: NotificationAuthorizationState? = nil,
            schemaVersion: Int = 1
        ) {
            self.singletonKey = singletonKey
            self.isOnboardingCompleted = isOnboardingCompleted
            self.parentPINCredentialKey = hasParentPIN ? Self.parentPINKeychainAccount : nil
            self.lastInstanceGenerationAt = lastInstanceGenerationAt
            self.lastNotificationSchedulingAt = lastNotificationSchedulingAt
            self.schedulingHorizonDateKey = schedulingHorizonDateKey
            self.lastNotificationAuthorizationRawValue = lastNotificationAuthorization?.rawValue
            self.schemaVersion = schemaVersion
        }

        /// 是否已有可供 Keychain 服务读取的家长 PIN 凭据引用。
        var hasParentPIN: Bool {
            parentPINCredentialKey != nil
        }

        /// 在 Keychain 服务成功写入凭据后记录固定查找键。
        func markParentPINStored() {
            parentPINCredentialKey = Self.parentPINKeychainAccount
        }

        /// 在 Keychain 服务成功删除凭据后清除查找键。
        func clearParentPINReference() {
            parentPINCredentialKey = nil
        }

        var lastNotificationAuthorization: NotificationAuthorizationState? {
            guard let lastNotificationAuthorizationRawValue else { return nil }
            return NotificationAuthorizationState(rawValue: lastNotificationAuthorizationRawValue)
        }

        /// 记录最近一次从系统读取的通知总授权状态，不据此推断提醒或声音开关。
        func recordNotificationAuthorization(_ authorization: NotificationAuthorizationState) {
            lastNotificationAuthorizationRawValue = authorization.rawValue
        }
    }
}
