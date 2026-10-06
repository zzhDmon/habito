import Foundation
import SwiftData

/// 主 actor 内短暂持有本次编辑前的对象图；只用于失败恢复，不是新的持久化模型。
///
/// iPadOS 17 的 rollback 不总会恢复已载入的 Swift 标量/逆关系缓存。先恢复本次会改的
/// 值和关系，再 rollback 清除插入/删除标记；不补偿 save，也不接触已有脏事务。
@MainActor
struct TaskTemplateEditRollbackSnapshot {
    private let restoreTemplate: () -> Void
    private let restoreOccurrences: [() -> Void]

    /// 在任何修改之前读取完整相关图；查询失败时编辑尚未开始。
    init(context: ModelContext, template: TaskTemplate, rule: ReminderRule) throws {
        let title = template.title
        let icon = template.iconName
        let color = template.colorToken
        let duration = template.targetDurationSeconds
        let enabled = template.isEnabled
        let revision = template.revision
        let updatedAt = template.updatedAt
        let category = template.categoryRawValue
        let period = template.timePeriodRawValue
        let verification = template.verificationTypeRawValue
        let rewards = (template.xpReward, template.coinReward, template.activeBonusCoin)
        let recurrence = try rule.decodedRecurrence()
        let reminderMinutes = rule.timeOfDayMinutes
        let ruleEnabled = rule.isEnabled
        restoreTemplate = {
            template.title = title
            template.iconName = icon
            template.colorToken = color
            template.targetDurationSeconds = duration
            template.isEnabled = enabled
            template.revision = revision
            template.updatedAt = updatedAt
            template.categoryRawValue = category
            template.timePeriodRawValue = period
            template.verificationTypeRawValue = verification
            template.xpReward = rewards.0
            template.coinReward = rewards.1
            template.activeBonusCoin = rewards.2
            rule.update(recurrence: recurrence, timeOfDayMinutes: reminderMinutes, isEnabled: ruleEnabled)
        }
        let templateID = template.id
        let rows = try context.fetch(
            FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.templateID == templateID }))
        restoreOccurrences = try rows.map { row in
            let scheduledAt = row.scheduledAt
            let plannedAt = row.plannedAt
            let deadlineAt = row.deadlineAt
            let title = row.titleSnapshot
            let icon = row.iconSnapshot
            let color = row.colorSnapshot
            let duration = row.targetDurationSnapshot
            let revision = row.sourceRevision
            let detached = row.isDetachedOverride
            let updatedAt = row.updatedAt
            let category = row.categorySnapshotRawValue
            let period = row.timePeriodSnapshotRawValue
            let verification = row.verificationTypeSnapshotRawValue
            let rewards = (row.xpRewardSnapshot, row.coinRewardSnapshot, row.activeBonusCoinSnapshot)
            let originalTemplate = row.template
            let occurrenceID = row.id
            let completions = try context.fetch(
                FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
            let sessions = try context.fetch(
                FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
            let links = try context.fetch(
                FetchDescriptor<NotificationLink>(predicate: #Predicate { $0.occurrenceID == occurrenceID }))
            let completion = row.completionRecord
            let originalSessions = row.timerSessions
            let originalLinks = row.notificationLinks
            let completionRelationships = completions.map { ($0, $0.occurrence) }
            let sessionRelationships = sessions.map { ($0, $0.occurrence) }
            let linkRelationships = links.map { ($0, $0.occurrence) }
            return {
                row.scheduledAt = scheduledAt
                row.plannedAt = plannedAt
                row.deadlineAt = deadlineAt
                row.titleSnapshot = title
                row.iconSnapshot = icon
                row.colorSnapshot = color
                row.targetDurationSnapshot = duration
                row.sourceRevision = revision
                row.isDetachedOverride = detached
                row.updatedAt = updatedAt
                row.categorySnapshotRawValue = category
                row.timePeriodSnapshotRawValue = period
                row.verificationTypeSnapshotRawValue = verification
                row.xpRewardSnapshot = rewards.0
                row.coinRewardSnapshot = rewards.1
                row.activeBonusCoinSnapshot = rewards.2
                row.template = originalTemplate
                // 物化可能因星期/启停变化暂存删除，恢复关系后由 rollback 撤回删除标记。
                row.completionRecord = completion
                row.timerSessions = originalSessions
                row.notificationLinks = originalLinks
                // 冲正记录原本可没有当前逆关系，不能把历史记录重新挂成当前完成。
                for (record, occurrence) in completionRelationships { record.occurrence = occurrence }
                for (session, occurrence) in sessionRelationships { session.occurrence = occurrence }
                for (link, occurrence) in linkRelationships { link.occurrence = occurrence }
            }
        }
    }

    /// 恢复本卡可能修改的标量和维护性删除关系；调用方紧接着执行 rollback。
    func restore() {
        restoreTemplate()
        for restore in restoreOccurrences { restore() }
    }
}
