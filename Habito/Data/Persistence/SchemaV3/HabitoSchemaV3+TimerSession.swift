import Foundation
import SwiftData

// 冻结自 6ac9c83 的结构 4.0.0；后续演进不能修改这些历史字段。
extension HabitoSchemaV3 {
    /// 可跨前后台恢复的单次计时会话。
    ///
    /// 同一实例只能有一个未结束会话的约束需要查询现有数据后再写入，无法由 iPadOS 17
    /// 的 SwiftData 声明为条件唯一索引，因此由 M1-006 的事务服务集中保证。
    @Model
    final class TimerSession {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var occurrenceID: UUID
        var stateRawValue: String
        var startedAt: Date
        var lastResumedAt: Date
        var accumulatedActiveSeconds: TimeInterval
        var endedAt: Date?

        var occurrence: TaskOccurrence?

        init(
            id: UUID = UUID(),
            occurrenceID: UUID,
            state: TimerSessionState,
            startedAt: Date,
            lastResumedAt: Date,
            accumulatedActiveSeconds: TimeInterval = 0,
            endedAt: Date? = nil
        ) {
            self.id = id
            self.occurrenceID = occurrenceID
            self.stateRawValue = state.rawValue
            self.startedAt = startedAt
            self.lastResumedAt = lastResumedAt
            self.accumulatedActiveSeconds = accumulatedActiveSeconds
            self.endedAt = endedAt
        }

        var state: TimerSessionState? {
            TimerSessionState(rawValue: stateRawValue)
        }
    }
}
