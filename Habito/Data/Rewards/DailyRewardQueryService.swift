import Foundation
import SwiftData

/// 在主 actor 同步读取已保存账本，不发奖、不保存，也不清理调用方的编辑。
@MainActor
struct DailyRewardQueryService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar, timeZone: TimeZone) {
        self.context = context
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        self.calendar = localCalendar
    }

    /// 查询当地当天截至指定时刻的有效收入，不将累计余额或预期奖励冒充所得。
    ///
    /// - Parameter now: 调用方注入的查询时刻，避免业务层自行读取系统时间。
    /// - Returns: 当天未冲正收入之和；消费另计，不减少此值。
    /// - Throws: 未保存编辑、非法时间、损坏账本、所得溢出或持久化读取错误。
    /// - Important: 这是当前有效事实的日汇总，不是历史快照；已冲正收入在时钟回拨时也不会复活。
    func summary(at now: Date) throws -> DailyRewardSummary {
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite,
            let day = calendar.dateInterval(of: .day, for: now)
        else { throw RewardLedgerError.invalidTimestamp }
        let ledger = try RewardLedgerSnapshot(context: context)
        // 由日历确定日界，兼容夏令时的23/25小时；不纳入未来时刻或次日的收入。
        let rewards = ledger.xp.values.filter {
            $0.kind == .reward && $0.createdAt >= day.start && $0.createdAt < day.end
                && $0.createdAt <= now && ledger.xp[RewardLedgerKey.xpReversal($0.sourceID)] == nil
        }
        let xp = try RewardBalance.checkedTotal(rewards.map(\.amount))
        let coins = try rewards.map { reward in
            // Snapshot已校验成对交易；保持显式错误，不能用缺失时默认0掩盖损坏。
            guard let coin = ledger.coin[RewardLedgerKey.coinReward(reward.sourceID)] else {
                throw RewardLedgerError.corruptLedger(reward.businessKey)
            }
            return coin.amount
        }
        return DailyRewardSummary(earnedXP: xp, earnedCoins: try RewardBalance.checkedTotal(coins))
    }
}
