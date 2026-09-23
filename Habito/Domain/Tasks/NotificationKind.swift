import Foundation

/// 与任务实例关联的本地通知用途。
nonisolated enum NotificationKind: String, CaseIterable, Sendable {
    case primary
    case snooze
}
