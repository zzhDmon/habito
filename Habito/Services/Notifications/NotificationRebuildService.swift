import Foundation
import SwiftData

/// 从业务真相重建未来实例与主提醒，并同步系统请求及可审计映射。
@MainActor
struct NotificationRebuildService {
    static let defaultHorizonDays = 14
    static let minimumCoverageDays = 7

    private let context: ModelContext
    private let coordinator: NotificationReconciliationCoordinator
    private let selector = NotificationCandidateSelector()
    private let resolver = TaskCandidateOverrideResolver()
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let horizonDays: Int

    init(
        context: ModelContext,
        scheduler: any NotificationRequestScheduling,
        calendar: Calendar,
        timeZone: TimeZone,
        horizonDays: Int = Self.defaultHorizonDays
    ) {
        self.context = context
        coordinator = NotificationReconciliationCoordinator(scheduler: scheduler)
        self.calendar = calendar
        self.timeZone = timeZone
        self.horizonDays = horizonDays
        self.calendar.timeZone = timeZone
    }

    /// 生成滚动实例、选择预算内主提醒、核对系统队列并保存成功映射。
    func rebuild(at now: Date) async throws -> NotificationRebuildResult {
        try Task.checkCancellation()
        guard horizonDays >= Self.minimumCoverageDays else {
            throw NotificationRebuildError.invalidHorizonDays(horizonDays)
        }
        let today = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
        let availableThrough = try adding(days: horizonDays, to: today)
        let minimumCoverageThrough = try adding(days: Self.minimumCoverageDays, to: today)

        try materializeOccurrences(in: today...availableThrough, today: today, now: now)
        let candidates = try notificationCandidates(in: today...availableThrough)
        let selection = try selector.select(
            from: candidates,
            now: now,
            availableThrough: availableThrough,
            minimumCoverageThrough: minimumCoverageThrough
        )
        let requests = try makeRequests(from: selection.primaryCandidates)
        let reconciliation = await coordinator.reconcile(desiredRequests: requests)

        // `.task(id:)` 可能因更新的业务事件取消旧重建；旧任务不再写检查点，由新任务按最新真相修复映射。
        try Task.checkCancellation()
        try synchronizeLinks(requests: requests, report: reconciliation, at: now)
        if reconciliation.isSuccessful {
            let settings = try appSettings()
            settings.lastInstanceGenerationAt = now
            settings.lastNotificationSchedulingAt = now
            settings.schedulingHorizonDateKey = selection.coverageThrough.dateKey
            try context.save()
        }
        return NotificationRebuildResult(
            selection: selection,
            reconciliation: reconciliation
        )
    }

    private func materializeOccurrences(
        in range: ClosedRange<LocalDate>,
        today: LocalDate,
        now: Date
    ) throws {
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let overrides = try dayOverrides(in: range)
        let reconciler = TaskOccurrenceReconciliationService(context: context)
        let expander = TaskRecurrenceExpander(calendar: calendar, timeZone: timeZone)

        do {
            for template in templates {
                let existing = try occurrences(templateID: template.id, in: range)
                let candidates: [ResolvedTaskCandidate]
                if template.lifecycleState == .active {
                    guard let rule = template.reminderRule else {
                        throw NotificationRebuildError.missingRule(template.id)
                    }
                    guard rule.isEnabled else {
                        throw NotificationRebuildError.disabledRuleForActiveTemplate(template.id)
                    }
                    let generated = try expander.expand(
                        rule.decodedRecurrence(),
                        timeOfDayMinutes: rule.timeOfDayMinutes,
                        from: range.lowerBound,
                        through: range.upperBound
                    )
                    let detached: [ScheduledTaskCandidate] = try existing.compactMap { occurrence in
                        guard occurrence.isDetachedOverride else { return nil }
                        let date = try occurrenceDate(occurrence)
                        return ScheduledTaskCandidate(date: date, scheduledAt: occurrence.scheduledAt)
                    }
                    candidates = try resolver.resolve(
                        generated: generated,
                        templateRevision: template.revision,
                        dayOverrides: overrides,
                        detachedOverrides: detached
                    )
                } else {
                    candidates = []
                }
                _ = try reconciler.reconcile(
                    template: template,
                    candidates: candidates,
                    in: range,
                    today: today,
                    now: now,
                    savesChanges: false
                )
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func notificationCandidates(
        in range: ClosedRange<LocalDate>
    ) throws -> [NotificationSchedulingCandidate] {
        try context.fetch(FetchDescriptor<TaskOccurrence>()).compactMap { occurrence in
            let date = try occurrenceDate(occurrence)
            guard range.contains(date) else { return nil }
            guard let status = occurrence.status else {
                throw NotificationRebuildError.invalidOccurrenceStatus(
                    occurrence.id,
                    occurrence.statusRawValue
                )
            }
            guard status == .pending else { return nil }
            return NotificationSchedulingCandidate(
                occurrenceID: occurrence.id,
                date: date,
                scheduledAt: occurrence.scheduledAt
            )
        }
    }

    private func makeRequests(
        from candidates: [NotificationSchedulingCandidate]
    ) throws -> [TaskNotificationRequest] {
        let occurrencesByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskOccurrence>()).map {
                ($0.id, $0)
            }
        )
        return candidates.compactMap { candidate in
            guard let occurrence = occurrencesByID[candidate.occurrenceID] else { return nil }
            return TaskNotificationRequest(
                occurrenceID: candidate.occurrenceID,
                kind: .primary,
                title: occurrence.titleSnapshot,
                body: String(localized: "notification.taskBody"),
                scheduledAt: candidate.scheduledAt
            )
        }
    }

    private func synchronizeLinks(
        requests: [TaskNotificationRequest],
        report: NotificationReconciliationReport,
        at now: Date
    ) throws {
        let successful = Set(
            report.retainedIdentifiers + report.addedIdentifiers + report.replacedIdentifiers
        )
        let store = NotificationLinkStore(context: context)
        for request in requests where successful.contains(request.identifier) {
            try store.upsert(
                occurrenceID: request.occurrenceID,
                kind: request.kind,
                scheduledAt: request.scheduledAt,
                createdAt: now
            )
        }
        let removed = Set(report.removedIdentifiers)
        for link in try context.fetch(FetchDescriptor<NotificationLink>())
        where removed.contains(link.requestIdentifier) {
            context.delete(link)
        }
        try context.save()
    }

    private func occurrences(
        templateID: UUID,
        in range: ClosedRange<LocalDate>
    ) throws -> [TaskOccurrence] {
        try context.fetch(
            FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.templateID == templateID })
        ).filter { occurrence in
            range.contains(try occurrenceDate(occurrence))
        }
    }

    private func occurrenceDate(_ occurrence: TaskOccurrence) throws -> LocalDate {
        do {
            return try LocalDate(dateKey: occurrence.dateKey)
        } catch {
            throw NotificationRebuildError.invalidOccurrenceDate(occurrence.id, occurrence.dateKey)
        }
    }

    private func dayOverrides(
        in range: ClosedRange<LocalDate>
    ) throws -> [DayTypeOverrideValue] {
        try context.fetch(FetchDescriptor<DayOverride>()).compactMap { override in
            let date = try LocalDate(dateKey: override.dateKey)
            guard range.contains(date) else { return nil }
            guard let dayType = override.dayType else {
                throw NotificationRebuildError.invalidDayOverride(
                    override.id,
                    override.dayTypeRawValue
                )
            }
            return DayTypeOverrideValue(date: date, dayType: dayType)
        }
    }

    private func appSettings() throws -> AppSettings {
        let values = try context.fetch(FetchDescriptor<AppSettings>())
        guard values.count <= 1 else { throw NotificationRebuildError.duplicateAppSettings }
        if let value = values.first { return value }
        let value = AppSettings()
        context.insert(value)
        return value
    }

    private func adding(days: Int, to date: LocalDate) throws -> LocalDate {
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: 12
        )
        guard
            let start = calendar.date(from: components),
            let end = calendar.date(byAdding: .day, value: days, to: start)
        else {
            throw NotificationRebuildError.calendarCalculationFailed
        }
        return try LocalDate(date: end, calendar: calendar, timeZone: timeZone)
    }
}
