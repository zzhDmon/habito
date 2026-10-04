/// 防止维护性删除把其他 context 或未入库对象误当作当前事务的对象。
nonisolated enum TaskGraphDeletionError: Error, Equatable, Sendable {
    case modelNotInContext
}
