/// 只从有效交易派生的资产快照；等级阶段读取 XP，不另存一套成长余额。
nonisolated struct RewardBalance: Equatable, Sendable {
    let effectiveXP: Int
    let coins: Int

    /// 先抵消异号金额，再累加剩余同号值，避免 fetch 顺序制造假溢出。
    ///
    /// - Throws: 数学上的最终结果超出 Int 表达范围时明确报错。
    static func checkedTotal(_ amounts: [Int]) throws -> Int {
        var positive = amounts.lazy.filter { $0 >= 0 }.makeIterator()
        var negative = amounts.lazy.filter { $0 < 0 }.makeIterator()
        var total = 0
        while true {
            let next = total >= 0 ? (negative.next() ?? positive.next()) : (positive.next() ?? negative.next())
            guard let next else { return total }
            let addition = total.addingReportingOverflow(next)
            guard !addition.overflow else { throw RewardLedgerError.integerOverflow }
            total = addition.partialValue
        }
    }
}
