import Foundation

/// 通知映射不存在、损坏或与稳定标识冲突。
nonisolated enum NotificationLinkStoreError: Error, Equatable {
    case occurrenceNotFound(UUID)
    case invalidIdentifier(String)
    case invalidKind(identifier: String, rawValue: String)
    case inconsistentMapping(identifier: String)
    case unsavedChanges
}
