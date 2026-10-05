import Foundation
import SwiftData

// 冻结自 7c8b5ac 的结构 5.0.0；后续演进不能修改这些历史字段。
extension HabitoSchemaV4 {
    /// SwiftData 任务实例与系统本地通知请求之间的可审计映射。
    @Model
    final class NotificationLink {
        @Attribute(.unique) private(set) var requestIdentifier: String
        private(set) var occurrenceID: UUID
        var kindRawValue: String
        var scheduledAt: Date
        var createdAt: Date

        var occurrence: TaskOccurrence?

        init(
            requestIdentifier: String,
            occurrenceID: UUID,
            kind: NotificationKind,
            scheduledAt: Date,
            createdAt: Date = .now
        ) {
            self.requestIdentifier = requestIdentifier
            self.occurrenceID = occurrenceID
            self.kindRawValue = kind.rawValue
            self.scheduledAt = scheduledAt
            self.createdAt = createdAt
        }

        var kind: NotificationKind? {
            NotificationKind(rawValue: kindRawValue)
        }
    }
}
