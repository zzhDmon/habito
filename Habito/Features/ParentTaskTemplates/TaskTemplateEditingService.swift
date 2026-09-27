import Foundation
import SwiftData

/// 以单一事务加载、创建或更新模板及其每周规则。
@MainActor
struct TaskTemplateEditingService {
    private let context: ModelContext
    private var calendar: Calendar
    private let timeZone: TimeZone

    init(context: ModelContext, calendar: Calendar, timeZone: TimeZone) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.calendar.timeZone = timeZone
    }

    /// 将持久化模板转换为编辑草稿。
    ///
    /// - Throws: 模板不存在、已归档、缺少规则或不是当前表单支持的每周规则时抛出错误。
    func load(templateID: UUID) throws -> TaskTemplateDraft {
        let template = try fetch(templateID)
        guard template.archivedAt == nil else {
            throw TaskTemplateEditorError.archivedTemplate(templateID)
        }
        guard let rule = template.reminderRule else {
            throw TaskTemplateEditorError.missingRule(templateID)
        }
        let recurrence = try rule.decodedRecurrence()
        guard recurrence.kind == .weekly else {
            throw TaskTemplateEditorError.unsupportedRecurrence(templateID)
        }
        return TaskTemplateDraft(
            templateID: template.id,
            title: template.title,
            iconName: template.iconName,
            colorToken: template.colorToken,
            timeOfDayMinutes: rule.timeOfDayMinutes,
            targetDurationMinutes: max(1, Int(ceil(template.targetDurationSeconds / 60))),
            weekdays: recurrence.weekdays,
            isEnabled: template.isEnabled && rule.isEnabled
        )
    }

    /// 校验并保存草稿，同时在同一事务中核对今天至既有边界的实例。
    ///
    /// - Returns: 新建或更新模板的稳定 ID。
    /// - Throws: 字段校验、目标查找、日期转换或 SwiftData 保存失败。
    func save(_ draft: TaskTemplateDraft, at now: Date) throws -> UUID {
        let title = try validatedTitle(draft.title)
        try validate(draft)
        let today = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)

        if let templateID = draft.templateID {
            let template = try fetch(templateID)
            guard template.archivedAt == nil else {
                throw TaskTemplateEditorError.archivedTemplate(templateID)
            }
            guard let rule = template.reminderRule else {
                throw TaskTemplateEditorError.missingRule(templateID)
            }
            let existingRecurrence = try rule.decodedRecurrence()
            guard existingRecurrence.kind == .weekly else {
                throw TaskTemplateEditorError.unsupportedRecurrence(templateID)
            }
            let recurrence = try TaskRecurrence.weekly(
                on: draft.weekdays,
                starting: existingRecurrence.startDate,
                ending: existingRecurrence.endDate
            )
            apply(draft, title: title, to: template, at: now)
            rule.update(
                recurrence: recurrence,
                timeOfDayMinutes: draft.timeOfDayMinutes,
                isEnabled: draft.isEnabled
            )
            try materializeAndSave(template, today: today, now: now)
            return template.id
        }

        let template = TaskTemplate(
            title: title,
            iconName: draft.iconName,
            colorToken: draft.colorToken,
            targetDurationSeconds: TimeInterval(draft.targetDurationMinutes * 60),
            isEnabled: draft.isEnabled,
            createdAt: now,
            updatedAt: now
        )
        let recurrence = try TaskRecurrence.weekly(on: draft.weekdays, starting: today)
        let rule = ReminderRule(
            taskTemplateID: template.id,
            recurrence: recurrence,
            timeOfDayMinutes: draft.timeOfDayMinutes,
            isEnabled: draft.isEnabled
        )
        template.reminderRule = rule
        rule.taskTemplate = template
        context.insert(template)
        context.insert(rule)
        try materializeAndSave(template, today: today, now: now)
        return template.id
    }

    /// 模板与实例必须一起成功；任一核对错误都回滚本次复合写入。
    private func materializeAndSave(
        _ template: TaskTemplate,
        today: LocalDate,
        now: Date
    ) throws {
        do {
            _ = try TaskOccurrenceMaterializationService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            ).reconcile(
                template: template,
                today: today,
                now: now,
                savesChanges: false
            )
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func fetch(_ id: UUID) throws -> TaskTemplate {
        let descriptor = FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == id })
        guard let template = try context.fetch(descriptor).first else {
            throw TaskTemplateEditorError.templateNotFound(id)
        }
        return template
    }

    private func validatedTitle(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TaskTemplateEditorError.titleRequired }
        guard value.count <= 40 else { throw TaskTemplateEditorError.titleTooLong }
        return value
    }

    private func validate(_ draft: TaskTemplateDraft) throws {
        guard (1...180).contains(draft.targetDurationMinutes) else {
            throw TaskTemplateEditorError.invalidDuration
        }
        guard !draft.weekdays.isEmpty else { throw TaskTemplateEditorError.noWeekdays }
        guard TaskTemplateDraft.allowedIconNames.contains(draft.iconName) else {
            throw TaskTemplateEditorError.unsupportedIcon
        }
        guard TaskTemplateDraft.allowedColorTokens.contains(draft.colorToken) else {
            throw TaskTemplateEditorError.unsupportedColor
        }
        guard (0..<24 * 60).contains(draft.timeOfDayMinutes) else {
            throw TaskTemplateEditorError.invalidTime
        }
    }

    private func apply(
        _ draft: TaskTemplateDraft,
        title: String,
        to template: TaskTemplate,
        at now: Date
    ) {
        template.title = title
        template.iconName = draft.iconName
        template.colorToken = draft.colorToken
        template.targetDurationSeconds = TimeInterval(draft.targetDurationMinutes * 60)
        template.isEnabled = draft.isEnabled
        template.revision += 1
        template.updatedAt = now
    }
}
