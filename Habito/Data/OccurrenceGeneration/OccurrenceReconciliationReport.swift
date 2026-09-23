/// 一次实例核对实际执行的变更统计，便于测试和后续诊断日志使用。
struct OccurrenceReconciliationReport: Equatable, Sendable {
    let insertedCount: Int
    let updatedCount: Int
    let deletedCount: Int
    let protectedCount: Int
}
