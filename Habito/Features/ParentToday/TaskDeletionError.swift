/// 删除前的状态重验失败，不应修改任何任务或通知。
nonisolated enum TaskDeletionError: Error {
    case pendingChanges
    case unavailable
    case notRecurring
    case revisionOverflow
    case invalidTime
}
