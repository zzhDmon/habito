import Foundation

/// 本次自行确认冻结的奖励事实；截止时间不参加扣奖，自主性只比较提交与提醒快照。
nonisolated struct CompletionRewardSnapshot: Equatable, Sendable {
    let submittedAt: Date
    let reminderAt: Date
    let xp: Int
    let baseCoins: Int
    let autonomyBonusCoins: Int
    let settledCoins: Int
    let timing: CompletionTiming

    /// 参数来自实例配置，不在结算时读取模板或产品默认。
    ///
    /// - Throws: 负奖励、无效时间或实际 Coin 加总溢出时拒绝，不截断金额。
    init(submittedAt: Date, reminderAt: Date, xp: Int, baseCoins: Int, autonomyBonusCoins: Int) throws {
        guard xp >= 0, baseCoins >= 0, autonomyBonusCoins >= 0 else { throw RewardLedgerError.invalidAmount }
        guard submittedAt.timeIntervalSinceReferenceDate.isFinite, reminderAt.timeIntervalSinceReferenceDate.isFinite
        else {
            throw RewardLedgerError.invalidTimestamp
        }
        let timing = CompletionTiming.classify(submittedAt: submittedAt, reminderAt: reminderAt)
        let addition = baseCoins.addingReportingOverflow(timing == .beforeReminder ? autonomyBonusCoins : 0)
        guard !addition.overflow else { throw RewardLedgerError.integerOverflow }
        self.submittedAt = submittedAt
        self.reminderAt = reminderAt
        self.xp = xp
        self.baseCoins = baseCoins
        self.autonomyBonusCoins = autonomyBonusCoins
        self.settledCoins = addition.partialValue
        self.timing = timing
    }
}
