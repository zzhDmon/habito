import Foundation
import SwiftData

// 冻结自 45a7172 的结构 3.0.0；后续模型演进不可修改这些历史字段。
extension HabitoSchemaV2 {
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
        /// 旧记录缺少自主性证据，迁移保持未知；新用例须提供提交时刻的判定，不能回算旧历史。
        var completionTimingRawValue: String = "unknown"

        var occurrence: TaskOccurrence?

        init(
            id: UUID = UUID(),
            occurrenceID: UUID,
            completedAt: Date,
            activeDurationSeconds: TimeInterval,
            completionSource: CompletionSource,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            completionTiming: CompletionTiming = .unknown
        ) {
            self.id = id
            self.occurrenceID = occurrenceID
            self.completedAt = completedAt
            self.activeDurationSeconds = activeDurationSeconds
            self.completionSourceRawValue = completionSource.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completionTimingRawValue = completionTiming.rawValue
        }

        var completionTiming: CompletionTiming? { CompletionTiming(rawValue: completionTimingRawValue) }

        var completionSource: CompletionSource? {
            CompletionSource(rawValue: completionSourceRawValue)
        }
    }
}
