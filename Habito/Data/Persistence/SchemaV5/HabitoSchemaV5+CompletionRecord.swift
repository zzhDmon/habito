import Foundation
import SwiftData

// 冻结自 cdce127 的结构 6.0.0；历史字段与关系不能随当前模型演进。
extension HabitoSchemaV5 {
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
        /// 0 为旧写路径，1 为自行确认结算，2 为关联原提交的家长通过；不以零金额判断是否结算。
        private(set) var rewardSettlementVersion: Int = 0
        /// 撤销保留原记录与事件 ID；审计撤销用例负责校验余额、窗口与原交易。
        var revokedAt: Date?

        /// 家长验收关联哪次提交；旧记录保持空，不能从当前配置补造提交。
        private(set) var submissionID: UUID?
        /// 真实入账时刻与 completedAt 的提交事实分开；旧自行确认仍按原完成时刻核对。
        private(set) var rewardSettledAt: Date?

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
            revokedAt: Date? = nil,
            submissionID: UUID? = nil,
            rewardSettledAt: Date? = nil
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
            self.submissionID = submissionID
            self.rewardSettledAt = rewardSettledAt
        }

        var completionTiming: CompletionTiming? { CompletionTiming(rawValue: completionTimingRawValue) }

        var completionSource: CompletionSource? {
            CompletionSource(rawValue: completionSourceRawValue)
        }
    }
}
