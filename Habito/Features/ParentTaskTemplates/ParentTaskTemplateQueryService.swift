import Foundation
import SwiftData

/// 查询未归档模板，并用领域规则计算每个启用模板的下一次计划。
@MainActor
struct ParentTaskTemplateQueryService {
    private let context: ModelContext
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let expander: TaskRecurrenceExpander

    init(context: ModelContext, calendar: Calendar, timeZone: TimeZone) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.calendar.timeZone = timeZone
        expander = TaskRecurrenceExpander(calendar: calendar, timeZone: timeZone)
    }

    /// 返回与本地存储一致的列表快照。
    ///
    /// 软删除模板不会进入普通列表。启用模板优先，其次按下一次计划、更新时间和稳定 ID
    /// 排序；停用模板继续展示，但不生成下一次计划，避免让家长误以为仍会执行。
    func items(at now: Date) throws -> [ParentTaskTemplateListItem] {
        let descriptor = FetchDescriptor<TaskTemplate>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        let today = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
        let items = try context.fetch(descriptor).map { template in
            guard
                !template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !template.iconName.isEmpty,
                template.targetDurationSeconds > 0
            else {
                throw ParentTaskTemplateQueryError.invalidTemplate(template.id)
            }

            let nextScheduledAt = try nextScheduledAt(for: template, today: today, now: now)
            return ParentTaskTemplateListItem(
                id: template.id,
                title: template.title,
                iconName: template.iconName,
                targetDurationSeconds: template.targetDurationSeconds,
                lifecycleState: template.lifecycleState,
                nextScheduledAt: nextScheduledAt,
                updatedAt: template.updatedAt
            )
        }

        return items.sorted(by: precedes)
    }

    /// 包含归档配置和历史实例；普通列表为空不意味着家庭从未使用。
    func hasTaskConfiguration() throws -> Bool {
        try context.fetchCount(FetchDescriptor<TaskTemplate>()) > 0
            || context.fetchCount(FetchDescriptor<TaskOccurrence>()) > 0
    }

    private func nextScheduledAt(
        for template: TaskTemplate,
        today: LocalDate,
        now: Date
    ) throws -> Date? {
        guard
            template.lifecycleState == .active,
            let rule = template.reminderRule,
            rule.isEnabled
        else {
            return nil
        }

        let recurrence = try rule.decodedRecurrence()
        let searchStart = max(today, recurrence.startDate)
        let searchEnd: LocalDate
        switch recurrence.kind {
        case .once:
            searchEnd = recurrence.oneOffDate ?? searchStart
        case .weekly:
            // 每周规则在任意连续 7 天内必有一次命中；从生效日开始搜索也支持远期规则。
            searchEnd = try addingDays(7, to: searchStart)
        }
        // 一次性规则可能已早于今天结束；它是正常的“无后续计划”，不是损坏数据。
        guard searchStart <= searchEnd else { return nil }

        return try expander.expand(
            recurrence,
            timeOfDayMinutes: rule.timeOfDayMinutes,
            from: searchStart,
            through: searchEnd
        )
        .first { $0.scheduledAt >= now }?
        .scheduledAt
    }

    private func addingDays(_ days: Int, to localDate: LocalDate) throws -> LocalDate {
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: localDate.year,
            month: localDate.month,
            day: localDate.day,
            hour: 12
        )
        guard
            let reference = calendar.date(from: components),
            let advanced = calendar.date(byAdding: .day, value: days, to: reference),
            let result = try? LocalDate(date: advanced, calendar: calendar, timeZone: timeZone)
        else {
            throw ParentTaskTemplateQueryError.cannotAdvanceDate(localDate)
        }
        return result
    }

    private func precedes(
        _ lhs: ParentTaskTemplateListItem,
        _ rhs: ParentTaskTemplateListItem
    ) -> Bool {
        if lhs.lifecycleState != rhs.lifecycleState {
            return lhs.lifecycleState == .active
        }
        switch (lhs.nextScheduledAt, rhs.nextScheduledAt) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
