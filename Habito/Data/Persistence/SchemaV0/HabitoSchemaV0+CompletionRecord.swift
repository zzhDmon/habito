import Foundation
import SwiftData

// 冻结自 1b5591b 的 V0 模型；迁移依赖此历史定义，不能随当前模型一起修改。
extension HabitoSchemaV0 {
    /// 任务实例的实际完成事实；与“当天应该做什么”的实例状态分开保存。
    @Model
    final class CompletionRecord {
        @Attribute(.unique) private(set) var id: UUID
        @Attribute(.unique) private(set) var occurrenceID: UUID
        var completedAt: Date
        var activeDurationSeconds: TimeInterval
        var completionSourceRawValue: String
        var createdAt: Date
        var updatedAt: Date

        var occurrence: TaskOccurrence?

        init(
            id: UUID = UUID(),
            occurrenceID: UUID,
            completedAt: Date,
            activeDurationSeconds: TimeInterval,
            completionSource: CompletionSource,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.occurrenceID = occurrenceID
            self.completedAt = completedAt
            self.activeDurationSeconds = activeDurationSeconds
            self.completionSourceRawValue = completionSource.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        var completionSource: CompletionSource? {
            CompletionSource(rawValue: completionSourceRawValue)
        }
    }
}
