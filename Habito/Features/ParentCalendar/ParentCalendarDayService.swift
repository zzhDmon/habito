import Foundation
import SwiftData

/// 查询、预览并以单个事务应用家长日期覆盖。
///
/// 服务将日期覆盖和任务实例重建放在同一 `ModelContext` 中；任一模板
/// 校验失败都会回滚，避免留下“覆盖已写入、实例未同步”的中间状态。
@MainActor
struct ParentCalendarDayService {
    private let context: ModelContext
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let expander: TaskRecurrenceExpander
    private let resolver = TaskCandidateOverrideResolver()

    init(context: ModelContext, calendar: Calendar, timeZone: TimeZone) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.calendar.timeZone = timeZone
        expander = TaskRecurrenceExpander(calendar: calendar, timeZone: timeZone)
    }

    func snapshot(for date: LocalDate, today: LocalDate) throws -> ParentCalendarDaySnapshot {
        let override = try currentOverride(on: date)
        let occurrences = try occurrences(on: date).map { occurrence in
            guard let status = occurrence.status else {
                throw ParentCalendarDayError.invalidOccurrenceStatus(
                    id: occurrence.id,
                    value: occurrence.statusRawValue
                )
            }
            return ParentCalendarOccurrenceItem(
                id: occurrence.id,
                title: occurrence.titleSnapshot,
                scheduledAt: occurrence.scheduledAt,
                status: status,
                isDetachedOverride: occurrence.isDetachedOverride
            )
        }.sorted { $0.scheduledAt < $1.scheduledAt }

        return ParentCalendarDaySnapshot(
            date: date,
            naturalDayType: try naturalDayType(on: date),
            overrideDayType: override?.dayType,
            isHistorical: date < today,
            occurrences: occurrences
        )
    }

    /// 纯读计算将新增、删除和保护的实例数，供确认对话框展示。
    func preview(
        _ action: ParentCalendarDayAction,
        on date: LocalDate,
        today: LocalDate
    ) throws -> ParentCalendarDayImpact {
        guard date >= today else { throw ParentCalendarDayError.historicalDate(date) }
        _ = try currentOverride(on: date)
        let plans = try reconciliationPlans(for: date, dayType: action.dayType)
        var inserted = 0
        var deleted = 0
        var protected = 0

        for plan in plans {
            if plan.candidates.isEmpty {
                for occurrence in plan.existing {
                    guard let status = occurrence.status else {
                        throw ParentCalendarDayError.invalidOccurrenceStatus(
                            id: occurrence.id,
                            value: occurrence.statusRawValue
                        )
                    }
                    let preservesHistory = try TaskSubmissionHistory(context: context).preservesOccurrenceHistory(
                        occurrence)
                    if status == .pending, !occurrence.isDetachedOverride, !preservesHistory {
                        deleted += 1
                    } else {
                        protected += 1
                    }
                }
            } else if plan.existing.isEmpty {
                inserted += 1
            } else {
                for occurrence in plan.existing {
                    guard let status = occurrence.status else {
                        throw ParentCalendarDayError.invalidOccurrenceStatus(
                            id: occurrence.id,
                            value: occurrence.statusRawValue
                        )
                    }
                    let isWaiting =
                        try TaskSubmissionHistory(context: context).latest(for: occurrence)?.reviewState == .waiting
                    if status != .pending || occurrence.isDetachedOverride || isWaiting {
                        protected += 1
                    }
                }
            }
        }

        return ParentCalendarDayImpact(
            date: date,
            action: action,
            insertedCount: inserted,
            deletedCount: deleted,
            protectedCount: protected
        )
    }

    /// 写入覆盖并立即核对选中日期的全部模板实例。
    @discardableResult
    func apply(
        _ action: ParentCalendarDayAction,
        on date: LocalDate,
        today: LocalDate,
        now: Date
    ) throws -> OccurrenceReconciliationReport {
        guard date >= today else { throw ParentCalendarDayError.historicalDate(date) }
        // 先验证全部保护事实再修改日期覆盖；坏等待不能导致 17 的覆盖标量缓存留下半更新。
        _ = try preview(action, on: date, today: today)

        do {
            try updateOverride(action, on: date, now: now)
            let plans = try reconciliationPlans(for: date, dayType: action.dayType)
            let reconciler = TaskOccurrenceReconciliationService(context: context)
            var total = OccurrenceReconciliationReport(
                insertedCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                protectedCount: 0
            )

            for plan in plans {
                let report = try reconciler.reconcile(
                    template: plan.template,
                    candidates: plan.candidates,
                    in: date...date,
                    today: today,
                    now: now,
                    savesChanges: false
                )
                total = OccurrenceReconciliationReport(
                    insertedCount: total.insertedCount + report.insertedCount,
                    updatedCount: total.updatedCount + report.updatedCount,
                    deletedCount: total.deletedCount + report.deletedCount,
                    protectedCount: total.protectedCount + report.protectedCount
                )
            }
            try context.save()
            return total
        } catch {
            context.rollback()
            throw error
        }
    }

    private func reconciliationPlans(
        for date: LocalDate,
        dayType: DayType?
    ) throws -> [ParentCalendarReconciliationPlan] {
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let existing = try occurrences(on: date)
        let templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        for occurrence in existing where templatesByID[occurrence.templateID] == nil {
            throw ParentCalendarDayError.missingTemplate(occurrenceID: occurrence.id)
        }

        return try templates.map { template in
            let templateOccurrences = existing.filter { $0.templateID == template.id }
            let generated = try generatedCandidate(for: template, on: date)
            let detached = templateOccurrences.filter(\.isDetachedOverride).map {
                ScheduledTaskCandidate(date: date, scheduledAt: $0.scheduledAt)
            }
            let candidates: [ResolvedTaskCandidate]
            if template.lifecycleState == .active {
                candidates = try resolver.resolve(
                    generated: generated,
                    templateRevision: template.revision,
                    dayOverrides: dayType.map { [DayTypeOverrideValue(date: date, dayType: $0)] } ?? [],
                    detachedOverrides: detached
                )
            } else {
                candidates = []
            }
            return ParentCalendarReconciliationPlan(
                template: template,
                candidates: candidates,
                existing: templateOccurrences
            )
        }
    }

    private func generatedCandidate(
        for template: TaskTemplate,
        on date: LocalDate
    ) throws -> [ScheduledTaskCandidate] {
        guard
            template.lifecycleState == .active,
            let rule = template.reminderRule,
            rule.isEnabled
        else { return [] }
        return try expander.expand(
            rule.decodedRecurrence(),
            timeOfDayMinutes: rule.timeOfDayMinutes,
            from: date,
            through: date
        )
    }

    private func updateOverride(
        _ action: ParentCalendarDayAction,
        on date: LocalDate,
        now: Date
    ) throws {
        let current = try currentOverride(on: date)
        guard let dayType = action.dayType else {
            if let current { context.delete(current) }
            return
        }
        if let current {
            current.dayTypeRawValue = dayType.rawValue
            current.updatedAt = now
        } else {
            context.insert(DayOverride(date: date, dayType: dayType, updatedAt: now))
        }
    }

    private func currentOverride(on date: LocalDate) throws -> DayOverride? {
        let dateKey = date.dateKey
        let values = try context.fetch(
            FetchDescriptor<DayOverride>(predicate: #Predicate { $0.dateKey == dateKey })
        )
        guard values.count <= 1 else { throw ParentCalendarDayError.duplicateOverride(date) }
        if let value = values.first, value.dayType == nil {
            throw ParentCalendarDayError.invalidOverrideType(
                id: value.id,
                value: value.dayTypeRawValue
            )
        }
        return values.first
    }

    private func occurrences(on date: LocalDate) throws -> [TaskOccurrence] {
        let dateKey = date.dateKey
        return try context.fetch(
            FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.dateKey == dateKey })
        )
    }

    private func naturalDayType(on date: LocalDate) throws -> DayType {
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: 12
        )
        guard let instant = calendar.date(from: components) else {
            throw LocalDateError.invalidComponents(year: date.year, month: date.month, day: date.day)
        }
        return calendar.isDateInWeekend(instant) ? .holiday : .schoolDay
    }
}
