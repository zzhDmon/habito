/// 一次完整通知重建的实例覆盖与系统核对结果。
nonisolated struct NotificationRebuildResult: Equatable, Sendable {
    let selection: NotificationCandidateSelection
    let reconciliation: NotificationReconciliationReport
}
