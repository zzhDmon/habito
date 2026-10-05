import Foundation
import SwiftData

// 冻结自 6ac9c83 的结构 4.0.0；后续演进不能修改这些历史字段。
extension HabitoSchemaV3 {
    /// 任务实例的实际完成事实；与“当天应该做什么”的实例状态分开保存。
    @Model
    final class CompletionRecord {
        @Attribute(.unique) private(set) var id: UUID
        /// 同实例允许保留已撤销历史；业务事务维护唯一未撤销记录，不靠 unique upsert 覆盖审计。
        private(set) var occurrenceID: UUID
        var completedAt: Date
        var activeDurationSeconds: TimeInterval
        var completionSourceRawValue: String
        var createdAt: Date
        var updatedAt: Date
        /// 旧记录缺少自主性证据，迁移保持未知；新用例须提供提交时刻的判定，不能回算旧历史。
        var completionTimingRawValue: String = "unknown"

        /// 新用例冻结本次提交；旧记录缺少证据，保持空/零，不从当前模板补算。
        private(set) var reminderAtSnapshot: Date?
        private(set) var xpRewardSnapshot: Int = 0
        private(set) var coinRewardSnapshot: Int = 0
        private(set) var activeBonusCoinSnapshot: Int = 0
        private(set) var settledCoinSnapshot: Int = 0
        /// 0 表示旧写路径，1 表示新事务已冻结并结算；不以金额是否为零判断是否结算。
        private(set) var rewardSettlementVersion: Int = 0
        /// 撤销保留原记录与事件 ID；具体业务合法性由下一阶段撤销用例校验。
        var revokedAt: Date?

        var occurrence: TaskOccurrence?

        /// 构造完成事实；旧写路径保留兼容零/空，新结算用例必须显式注入快照和版本。
        ///
        /// - Important: 构造器不自行发奖，也不以结算版本代替账本校验；合法性与原子保存由用例负责。
        init(
            id: UUID = UUID(),
            occurrenceID: UUID,
            completedAt: Date,
            activeDurationSeconds: TimeInterval,
            completionSource: CompletionSource,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            completionTiming: CompletionTiming = .unknown,
            reminderAtSnapshot: Date? = nil,
            xpRewardSnapshot: Int = 0,
            coinRewardSnapshot: Int = 0,
            activeBonusCoinSnapshot: Int = 0,
            settledCoinSnapshot: Int = 0,
            rewardSettlementVersion: Int = 0,
            revokedAt: Date? = nil
        ) {
            self.id = id
            self.occurrenceID = occurrenceID
            self.completedAt = completedAt
            self.activeDurationSeconds = activeDurationSeconds
            self.completionSourceRawValue = completionSource.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completionTimingRawValue = completionTiming.rawValue
            self.reminderAtSnapshot = reminderAtSnapshot
            self.xpRewardSnapshot = xpRewardSnapshot
            self.coinRewardSnapshot = coinRewardSnapshot
            self.activeBonusCoinSnapshot = activeBonusCoinSnapshot
            self.settledCoinSnapshot = settledCoinSnapshot
            self.rewardSettlementVersion = rewardSettlementVersion
            self.revokedAt = revokedAt
        }

        var completionTiming: CompletionTiming? { CompletionTiming(rawValue: completionTimingRawValue) }

        var completionSource: CompletionSource? {
            CompletionSource(rawValue: completionSourceRawValue)
        }
    }
}
