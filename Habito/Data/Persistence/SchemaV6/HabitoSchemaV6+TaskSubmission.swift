import Foundation
import SwiftData

// 冻结自 8e98ca7 的结构 7.0.0；历史字段、默认与关系不能随活跃模型演进。
extension HabitoSchemaV6 {
    /// 家长验收的一次不可重算提交；重提创建新事件，旧审核事实与快照始终保留。
    ///
    /// 使用稳定实例外键而非级联关系，避免删除实例抹掉提交审计。所有活跃模型归属主 actor
    /// 的同一写上下文；构造器不保存/发奖，序号与状态转换由后续用例校验。
    @Model
    final class TaskSubmission {
        @Attribute(.unique) private(set) var id: UUID
        @Attribute(.unique) private(set) var businessKey: String
        private(set) var occurrenceID: UUID
        /// 同实例递增序号确定最新提交；不能只按可能相同的墙上时钟时间排序。
        private(set) var sequenceNumber: Int
        private(set) var submittedAt: Date
        private(set) var reminderAtSnapshot: Date
        private(set) var activeDurationSeconds: TimeInterval
        private(set) var xpRewardSnapshot: Int
        private(set) var coinRewardSnapshot: Int
        private(set) var activeBonusCoinSnapshot: Int
        private(set) var completionTimingRawValue: String
        var reviewStateRawValue: String = "waiting"
        var reviewedAt: Date?
        var reviewedCompletionID: UUID?

        /// 接受已验证奖励快照；审核结果可更新，但原提交时间/金额/时长不可改写。
        ///
        /// - Important: sequenceNumber 必须由同实例事务递增分配，唯一约束不能代替业务幂等。
        init(
            id: UUID = UUID(), occurrenceID: UUID, sequenceNumber: Int,
            snapshot: CompletionRewardSnapshot, activeDurationSeconds: TimeInterval,
            reviewState: SubmissionReviewState = .waiting,
            reviewedAt: Date? = nil, reviewedCompletionID: UUID? = nil
        ) {
            self.id = id
            self.occurrenceID = occurrenceID
            self.sequenceNumber = sequenceNumber
            self.businessKey = Self.makeBusinessKey(occurrenceID: occurrenceID, sequenceNumber: sequenceNumber)
            self.submittedAt = snapshot.submittedAt
            self.reminderAtSnapshot = snapshot.reminderAt
            self.activeDurationSeconds = activeDurationSeconds
            self.xpRewardSnapshot = snapshot.xp
            self.coinRewardSnapshot = snapshot.baseCoins
            self.activeBonusCoinSnapshot = snapshot.autonomyBonusCoins
            self.completionTimingRawValue = snapshot.timing.rawValue
            self.reviewStateRawValue = reviewState.rawValue
            self.reviewedAt = reviewedAt
            self.reviewedCompletionID = reviewedCompletionID
        }

        /// 原始值损坏返回 nil，查询/业务必须明确拒绝，不能当作待审核处理。
        var reviewState: SubmissionReviewState? { SubmissionReviewState(rawValue: reviewStateRawValue) }
        var completionTiming: CompletionTiming? { CompletionTiming(rawValue: completionTimingRawValue) }

        static func makeBusinessKey(occurrenceID: UUID, sequenceNumber: Int) -> String {
            "\(occurrenceID.uuidString.lowercased())|submission|\(sequenceNumber)"
        }
    }
}
