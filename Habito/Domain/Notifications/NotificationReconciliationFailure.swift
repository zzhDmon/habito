/// 增量核对中单个系统操作的可诊断失败。
nonisolated struct NotificationReconciliationFailure: Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case readPending
        case validateDesired
        case remove
        case add
        case replace
    }

    let identifier: String?
    let operation: Operation
    let message: String
}
