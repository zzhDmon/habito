/// XP 正常收入与纠错冲正；普通未完成不会创建扣减类型。
nonisolated enum XPTransactionKind: String, CaseIterable, Sendable {
    case reward
    case reversal
}
