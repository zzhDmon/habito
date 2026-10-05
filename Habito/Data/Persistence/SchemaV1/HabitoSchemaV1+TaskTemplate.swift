import Foundation
import SwiftData

// 冻结自 da08d63 的结构 2.0.0；后续模型演进不可修改这些历史字段。
extension HabitoSchemaV1 {
    /// 可重复生成每日任务实例的任务模板。
    ///
    /// 删除操作使用 `archivedAt` 软删除。即使发生维护性的物理删除，历史实例也会因
    /// `.nullify` 删除规则而保留，并继续使用自己的快照和 `templateID` 展示历史。
    /// 维护性物理删除应通过 `TaskGraphDeletionService`，显式兼容旧系统的关系清理行为。
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

        // 迁移必须有已确认的兼容默认；零奖励不是新的产品奖励方案，配置值后续由家长显式填写。
        var categoryRawValue: String = "unassigned"
        var timePeriodRawValue: String = "allDay"
        var verificationTypeRawValue: String = "selfConfirm"
        var xpReward: Int = 0
        var coinReward: Int = 0
        var activeBonusCoin: Int = 0

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
            archivedAt: Date? = nil,
            category: TaskCategory = .unassigned,
            timePeriod: TaskTimePeriod = .allDay,
            verificationType: TaskVerificationType = .selfConfirm,
            xpReward: Int = 0,
            coinReward: Int = 0,
            activeBonusCoin: Int = 0
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
            self.categoryRawValue = category.rawValue
            self.timePeriodRawValue = timePeriod.rawValue
            self.verificationTypeRawValue = verificationType.rawValue
            self.xpReward = xpReward
            self.coinReward = coinReward
            self.activeBonusCoin = activeBonusCoin
        }

        /// 损坏原始值返回空，由用例诊断；不能把无效分类静默变成合法“待设置”。
        var category: TaskCategory? { TaskCategory(rawValue: categoryRawValue) }
        var timePeriod: TaskTimePeriod? { TaskTimePeriod(rawValue: timePeriodRawValue) }
        var verificationType: TaskVerificationType? { TaskVerificationType(rawValue: verificationTypeRawValue) }

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
}
