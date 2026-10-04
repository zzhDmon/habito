/// 一次系统挂起请求核对的结果，可供日志和家长诊断页面查询。
nonisolated struct NotificationReconciliationReport: Equatable, Sendable {
    var retainedIdentifiers: [String] = []
    var addedIdentifiers: [String] = []
    var replacedIdentifiers: [String] = []
    var removedIdentifiers: [String] = []
    var removedDeliveredIdentifiers: [String] = []
    var failures: [NotificationReconciliationFailure] = []

    var isSuccessful: Bool {
        failures.isEmpty
    }
}
