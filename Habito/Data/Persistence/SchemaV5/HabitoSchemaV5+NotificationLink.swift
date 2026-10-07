import Foundation
import SwiftData

// 冻结自 cdce127 的结构 6.0.0；历史字段与关系不能随当前模型演进。
extension HabitoSchemaV5 {
    /// SwiftData 任务实例与系统本地通知请求之间的可审计映射。
    @Model
    final class NotificationLink {
        @Attribute(.unique) private(set) var requestIdentifier: String
        private(set) var occurrenceID: UUID
        var kindRawValue: String
        var scheduledAt: Date
        var createdAt: Date
        /// 显式稍后操作当时的最新提交 ID；nil 表示尚未有提交，不靠可能相同的时间戳猜轮次。
        ///
        /// 等待/退回重建用当前提交世代比较，防止清理前快速退回复活旧稍后；旧库迁移保持 nil。
        var submissionIDAtScheduling: UUID?

        var occurrence: TaskOccurrence?

        init(
            requestIdentifier: String,
            occurrenceID: UUID,
            kind: NotificationKind,
            scheduledAt: Date,
            createdAt: Date = .now,
            submissionIDAtScheduling: UUID? = nil
        ) {
            self.requestIdentifier = requestIdentifier
            self.occurrenceID = occurrenceID
            self.kindRawValue = kind.rawValue
            self.scheduledAt = scheduledAt
            self.createdAt = createdAt
            self.submissionIDAtScheduling = submissionIDAtScheduling
        }

        var kind: NotificationKind? {
            NotificationKind(rawValue: kindRawValue)
        }
    }
}
