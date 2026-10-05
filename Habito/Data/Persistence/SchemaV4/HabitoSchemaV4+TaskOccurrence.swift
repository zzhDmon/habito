import Foundation
import SwiftData

// 冻结自 7c8b5ac 的结构 5.0.0；后续演进不能修改这些历史字段。
extension HabitoSchemaV4 {
    /// 某个模板在特定本地日期上的任务实例。
    ///
    /// 快照字段保证模板后续改名或归档后，历史仍按发生当日的信息展示。
    /// 物理删除统一使用 `TaskGraphDeletionService` 清理拥有记录，不仅依赖 runtime 的级联规则。
    @Model
    final class TaskOccurrence {
        @Attribute(.unique) private(set) var id: UUID
        @Attribute(.unique) private(set) var uniquenessKey: String
        private(set) var templateID: UUID
        private(set) var dateKey: String
        var scheduledAt: Date
        var titleSnapshot: String
        var iconSnapshot: String
        var colorSnapshot: String
        var targetDurationSnapshot: TimeInterval
        var statusRawValue: String
        var sourceRevision: Int
        var isDetachedOverride: Bool
        var createdAt: Date
        var updatedAt: Date

        /// 实例配置快照与原提醒并存；提交阶段还要冻结该次提交，不从模板回算历史奖励。
        var categorySnapshotRawValue: String = "unassigned"
        var timePeriodSnapshotRawValue: String = "allDay"
        var verificationTypeSnapshotRawValue: String = "selfConfirm"
        var xpRewardSnapshot: Int = 0
        var coinRewardSnapshot: Int = 0
        var activeBonusCoinSnapshot: Int = 0
        var plannedAt: Date?
        var deadlineAt: Date?

        var template: TaskTemplate?

        @Relationship(deleteRule: .cascade, inverse: \CompletionRecord.occurrence)
        var completionRecord: CompletionRecord?

        @Relationship(deleteRule: .cascade, inverse: \TimerSession.occurrence)
        var timerSessions: [TimerSession] = []

        @Relationship(deleteRule: .cascade, inverse: \NotificationLink.occurrence)
        var notificationLinks: [NotificationLink] = []

        init(
            id: UUID = UUID(),
            templateID: UUID,
            date: LocalDate,
            scheduledAt: Date,
            titleSnapshot: String,
            iconSnapshot: String,
            colorSnapshot: String,
            targetDurationSnapshot: TimeInterval,
            status: TaskOccurrenceStatus = .pending,
            sourceRevision: Int,
            isDetachedOverride: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            categorySnapshot: TaskCategory = .unassigned,
            timePeriodSnapshot: TaskTimePeriod = .allDay,
            verificationTypeSnapshot: TaskVerificationType = .selfConfirm,
            xpRewardSnapshot: Int = 0,
            coinRewardSnapshot: Int = 0,
            activeBonusCoinSnapshot: Int = 0,
            plannedAt: Date? = nil,
            deadlineAt: Date? = nil
        ) {
            self.id = id
            self.uniquenessKey = Self.makeUniquenessKey(templateID: templateID, dateKey: date.dateKey)
            self.templateID = templateID
            self.dateKey = date.dateKey
            self.scheduledAt = scheduledAt
            self.titleSnapshot = titleSnapshot
            self.iconSnapshot = iconSnapshot
            self.colorSnapshot = colorSnapshot
            self.targetDurationSnapshot = targetDurationSnapshot
            self.statusRawValue = status.rawValue
            self.sourceRevision = sourceRevision
            self.isDetachedOverride = isDetachedOverride
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.categorySnapshotRawValue = categorySnapshot.rawValue
            self.timePeriodSnapshotRawValue = timePeriodSnapshot.rawValue
            self.verificationTypeSnapshotRawValue = verificationTypeSnapshot.rawValue
            self.xpRewardSnapshot = xpRewardSnapshot
            self.coinRewardSnapshot = coinRewardSnapshot
            self.activeBonusCoinSnapshot = activeBonusCoinSnapshot
            self.plannedAt = plannedAt
            self.deadlineAt = deadlineAt
        }

        var categorySnapshot: TaskCategory? { TaskCategory(rawValue: categorySnapshotRawValue) }
        var timePeriodSnapshot: TaskTimePeriod? { TaskTimePeriod(rawValue: timePeriodSnapshotRawValue) }
        var verificationTypeSnapshot: TaskVerificationType? {
            TaskVerificationType(rawValue: verificationTypeSnapshotRawValue)
        }

        /// 持久化原始值损坏时返回 `nil`，由调用方显示可诊断错误。
        var status: TaskOccurrenceStatus? {
            TaskOccurrenceStatus(rawValue: statusRawValue)
        }

        /// 将持久化的覆盖标记和来源版本组合为领域来源值。
        var origin: TaskOccurrenceOrigin {
            if isDetachedOverride {
                .detachedOverride
            } else {
                .generated(templateRevision: sourceRevision)
            }
        }

        /// 为 iPadOS 17 不支持复合唯一约束的 SwiftData 生成稳定业务键。
        static func makeUniquenessKey(templateID: UUID, dateKey: String) -> String {
            "\(templateID.uuidString.lowercased())|\(dateKey)"
        }
    }
}
