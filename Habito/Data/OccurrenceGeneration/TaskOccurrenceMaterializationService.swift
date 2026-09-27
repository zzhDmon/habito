import Foundation
import SwiftData

/// 将模板规则核对到“今天至现有最远实例”的已物化范围。
///
/// M3 只保证管理闭环，因此新模板至少生成今天的实例；若数据层已经存在更远实例，
/// 编辑或重新启用会同步到该既有边界。M4 的滚动通知排程再负责扩展未来覆盖天数。
@MainActor
struct TaskOccurrenceMaterializationService {
    private let context: ModelContext
    private let expander: TaskRecurrenceExpander
    private let resolver = TaskCandidateOverrideResolver()

    init(context: ModelContext, calendar: Calendar, timeZone: TimeZone) {
        self.context = context
        expander = TaskRecurrenceExpander(calendar: calendar, timeZone: timeZone)
    }

    /// 核对模板当前已物化范围，保留历史、已开始、已完成与单日覆盖实例。
    ///
    /// - Parameters:
    ///   - template: 已应用最新编辑或生命周期状态的模板。
    ///   - today: 注入的业务今天，也是允许修改实例的最早日期。
    ///   - now: 本次写入时间。
    ///   - savesChanges: 复合事务传 `false`，由外层统一保存或回滚。
    /// - Returns: 实际发生的实例变更统计。
    /// - Throws: 模板规则、日期覆盖或已有实例损坏，以及 SwiftData 查询或保存失败。
    func reconcile(
        template: TaskTemplate,
        today: LocalDate,
        now: Date,
        savesChanges: Bool = true
    ) throws -> OccurrenceReconciliationReport {
        let occurrences = try fetchOccurrences(templateID: template.id)
        let datedOccurrences = try occurrences.map { occurrence in
            do {
                return (occurrence, try LocalDate(dateKey: occurrence.dateKey))
            } catch {
                throw OccurrenceReconciliationError.invalidStoredDateKey(
                    occurrenceID: occurrence.id,
                    dateKey: occurrence.dateKey
                )
            }
        }
        let end = datedOccurrences.map(\.1).filter { $0 >= today }.max() ?? today
        let range = today...end

        let candidates: [ResolvedTaskCandidate]
        if template.lifecycleState == .active {
            guard let rule = template.reminderRule else {
                throw TaskOccurrenceMaterializationError.missingRule(template.id)
            }
            guard rule.isEnabled else {
                throw TaskOccurrenceMaterializationError.disabledRuleForActiveTemplate(template.id)
            }
            let generated = try expander.expand(
                rule.decodedRecurrence(),
                timeOfDayMinutes: rule.timeOfDayMinutes,
                from: today,
                through: end
            )
            let detached: [ScheduledTaskCandidate] = datedOccurrences.compactMap { element in
                let (occurrence, date) = element
                guard range.contains(date), occurrence.isDetachedOverride else { return nil }
                return ScheduledTaskCandidate(date: date, scheduledAt: occurrence.scheduledAt)
            }
            candidates = try resolver.resolve(
                generated: generated,
                templateRevision: template.revision,
                dayOverrides: try dayOverrides(in: range),
                detachedOverrides: detached
            )
        } else {
            candidates = []
        }

        return try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: candidates,
            in: range,
            today: today,
            now: now,
            savesChanges: savesChanges
        )
    }

    private func fetchOccurrences(templateID: UUID) throws -> [TaskOccurrence] {
        try context.fetch(
            FetchDescriptor<TaskOccurrence>(
                predicate: #Predicate { $0.templateID == templateID }
            )
        )
    }

    private func dayOverrides(
        in range: ClosedRange<LocalDate>
    ) throws -> [DayTypeOverrideValue] {
        try context.fetch(FetchDescriptor<DayOverride>()).compactMap { value in
            let date = try LocalDate(dateKey: value.dateKey)
            guard range.contains(date) else { return nil }
            guard let dayType = value.dayType else {
                throw TaskOccurrenceMaterializationError.invalidDayOverride(
                    id: value.id,
                    rawValue: value.dayTypeRawValue
                )
            }
            return DayTypeOverrideValue(date: date, dayType: dayType)
        }
    }
}
