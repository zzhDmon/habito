/// Coin 的收入、消费与纠错来源，便于审计；并非仅存一个可改写余额。
nonisolated enum CoinTransactionKind: String, CaseIterable, Sendable {
    case reward
    case spend
    case reversal
}
