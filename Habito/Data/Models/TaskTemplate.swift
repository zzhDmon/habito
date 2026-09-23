import Foundation
import SwiftData

/// 可重复生成每日任务实例的任务模板。
///
/// 删除操作使用 `archivedAt` 软删除。即使发生维护性的物理删除，历史实例也会因
/// `.nullify` 删除规则而保留，并继续使用自己的快照和 `templateID` 展示历史。
@Model
final class TaskTemplate {
    @Attribute(.unique) private(set) var id: UUID
    var title: String
    var iconName: String
    var colorToken: String
    var targetDurationSeconds: TimeInterval
    var isEnabled: Bool
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ReminderRule.taskTemplate)
    var reminderRule: ReminderRule?

    @Relationship(deleteRule: .nullify, inverse: \TaskOccurrence.template)
    var occurrences: [TaskOccurrence] = []

    init(
        id: UUID = UUID(),
        title: String,
        iconName: String,
        colorToken: String,
        targetDurationSeconds: TimeInterval,
        isEnabled: Bool = true,
        revision: Int = 1,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorToken = colorToken
        self.targetDurationSeconds = targetDurationSeconds
        self.isEnabled = isEnabled
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    /// 由持久化字段得到模板当前生命周期，避免各页面重复解释布尔值和归档时间。
    var lifecycleState: TaskTemplateLifecycleState {
        if archivedAt != nil {
            .archived
        } else if isEnabled {
            .active
        } else {
            .disabled
        }
    }
}
