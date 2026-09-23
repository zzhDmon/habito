import Foundation
import SwiftData

/// 预览并原子执行模板停用、启用和软删除。
///
/// 服务先完整验证现有实例，再改变模板状态。停用或归档时复用实例核对服务删除
/// 今天及未来仍可变的普通待处理实例；历史、已开始、已完成和单日覆盖实例始终保留。
@MainActor
struct TaskTemplateLifecycleService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 计算确认文案所需的准确影响数量，不修改持久化状态。
    func preview(
        templateID: UUID,
        action: TaskTemplateLifecycleAction,
        today: LocalDate
    ) throws -> TaskTemplateLifecycleImpact {
        let template = try fetchTemplate(templateID)
        _ = try template.lifecycleState.applying(action)
        guard template.reminderRule != nil else {
            throw TaskTemplateLifecycleError.missingRule(templateID)
        }

        let occurrences = try fetchOccurrences(templateID: templateID)
        var removableCount = 0
        var latestDate: LocalDate?
        for occurrence in occurrences {
            let date: LocalDate
            do {
                date = try LocalDate(dateKey: occurrence.dateKey)
            } catch {
                throw TaskTemplateLifecycleError.invalidOccurrenceDate(
                    occurrence.id,
                    occurrence.dateKey
                )
            }
            guard let status = occurrence.status else {
                throw TaskTemplateLifecycleError.invalidOccurrenceStatus(
                    occurrence.id,
                    occurrence.statusRawValue
                )
            }
            latestDate = max(latestDate ?? date, date)
            if action != .enable,
                date >= today,
                status == .pending,
                !occurrence.isDetachedOverride
            {
                removableCount += 1
            }
        }

        return TaskTemplateLifecycleImpact(
            templateID: template.id,
            title: template.title,
            action: action,
            removableOccurrenceCount: removableCount,
            preservedOccurrenceCount: occurrences.count - removableCount,
            latestOccurrenceDate: latestDate
        )
    }

    /// 重新计算影响并执行状态变更，避免用户确认期间数据变化导致预览过期。
    func perform(
        templateID: UUID,
        action: TaskTemplateLifecycleAction,
        today: LocalDate,
        now: Date
    ) throws -> TaskTemplateLifecycleResult {
        let impact = try preview(templateID: templateID, action: action, today: today)
        let template = try fetchTemplate(templateID)
        guard let rule = template.reminderRule else {
            throw TaskTemplateLifecycleError.missingRule(templateID)
        }
        let nextState = try template.lifecycleState.applying(action)

        apply(nextState, to: template, rule: rule, at: now)
        do {
            let report: OccurrenceReconciliationReport?
            if action == .enable {
                try context.save()
                report = nil
            } else {
                let end = max(today, impact.latestOccurrenceDate ?? today)
                report = try TaskOccurrenceReconciliationService(context: context).reconcile(
                    template: template,
                    candidates: [],
                    in: today...end,
                    today: today,
                    now: now
                )
            }
            return TaskTemplateLifecycleResult(impact: impact, reconciliationReport: report)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func apply(
        _ state: TaskTemplateLifecycleState,
        to template: TaskTemplate,
        rule: ReminderRule,
        at now: Date
    ) {
        switch state {
        case .active:
            template.isEnabled = true
            template.archivedAt = nil
            rule.isEnabled = true
        case .disabled:
            template.isEnabled = false
            rule.isEnabled = false
        case .archived:
            template.isEnabled = false
            template.archivedAt = now
            rule.isEnabled = false
        }
        template.revision += 1
        template.updatedAt = now
    }

    private func fetchTemplate(_ id: UUID) throws -> TaskTemplate {
        let descriptor = FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == id })
        guard let template = try context.fetch(descriptor).first else {
            throw TaskTemplateLifecycleError.templateNotFound(id)
        }
        return template
    }

    private func fetchOccurrences(templateID: UUID) throws -> [TaskOccurrence] {
        let descriptor = FetchDescriptor<TaskOccurrence>(
            predicate: #Predicate { $0.templateID == templateID }
        )
        return try context.fetch(descriptor)
    }
}
