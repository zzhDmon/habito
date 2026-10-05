import Foundation
import SwiftData

// 冻结自 1b5591b 的 V0 模型；迁移依赖此历史定义，不能随当前模型一起修改。
extension HabitoSchemaV0 {
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
