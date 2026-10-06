import Foundation
import SwiftData

/// 以单一事务加载、创建或更新模板及其每周规则。
@MainActor
struct TaskTemplateEditingService {
    private let context: ModelContext
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let saveChanges: (ModelContext) throws -> Void

    /// 注入同一主写上下文与时间环境；保存回调仅隔离系统持久化和测试失败边界。
    ///
    /// - Important: 保存回调应同步提交一次或抛错，不可先成功提交再报告失败。
    init(
        context: ModelContext, calendar: Calendar, timeZone: TimeZone,
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.saveChanges = saveChanges
        self.calendar.timeZone = timeZone
    }

    /// 将持久化模板转换为编辑草稿。
    ///
    /// - Throws: 模板/规则缺失或归档、不支持的规则、损坏类型/奖励/修订及非法时长。
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
        guard template.revision > 0 else { throw TaskTemplateEditorError.invalidStoredRevision(templateID) }
        guard let category = template.category else {
            throw OccurrenceReconciliationError.invalidTemplateConfiguration(
                templateID: templateID, field: "category", rawValue: template.categoryRawValue)
        }
        guard let period = template.timePeriod else {
            throw OccurrenceReconciliationError.invalidTemplateConfiguration(
                templateID: templateID, field: "timePeriod", rawValue: template.timePeriodRawValue)
        }
        guard let verification = template.verificationType else {
            throw OccurrenceReconciliationError.invalidTemplateConfiguration(
                templateID: templateID, field: "verificationType", rawValue: template.verificationTypeRawValue)
        }
        // Int 转换前限制有限范围，不能让损坏的 infinity/超大时长触发运行时陷阱。
        guard template.targetDurationSeconds.isFinite, template.targetDurationSeconds > 0,
            template.targetDurationSeconds <= 180 * 60
        else { throw TaskTemplateEditorError.invalidDuration }
        let draft = TaskTemplateDraft(
            templateID: template.id,
            title: template.title,
            iconName: template.iconName,
            colorToken: template.colorToken,
            timeOfDayMinutes: rule.timeOfDayMinutes,
            targetDurationMinutes: Int(ceil(template.targetDurationSeconds / 60)),
            weekdays: recurrence.weekdays,
            isEnabled: template.isEnabled && rule.isEnabled,
            category: category, timePeriod: period, verificationType: verification,
            xpReward: template.xpReward, coinReward: template.coinReward, activeBonusCoin: template.activeBonusCoin,
            plannedTimeOfDayMinutes: rule.plannedTimeOfDayMinutes,
            deadlineTimeOfDayMinutes: rule.deadlineTimeOfDayMinutes
        )
        try validate(draft)
        return draft
    }

    /// 校验并保存草稿，同时在同一事务中核对今天至既有边界的实例。
    ///
    /// - Returns: 新建或更新模板的稳定 ID。
    /// - Throws: 已有脏上下文、非法字段/时间、修订溢出、目标查找/物化或保存失败。
    func save(_ draft: TaskTemplateDraft, at now: Date) throws -> UUID {
        // 编辑服务拥有一次干净写事务；不能借保存或 rollback 提交/丢弃其他页面的未保存输入。
        guard !context.hasChanges else { throw TaskTemplateEditorError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
        let title = try validatedTitle(draft.title)
        try validate(draft)
        let today = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }

        if let templateID = draft.templateID {
            let template = try fetch(templateID)
            // 保存旧字段也先验证已有配置，不能让新草稿把损坏存储悄悄洗成默认值。
            _ = try load(templateID: templateID)
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
            let revision = template.revision.addingReportingOverflow(1)
            guard !revision.overflow else { throw TaskTemplateEditorError.revisionOverflow }
            let original = try TaskTemplateEditRollbackSnapshot(context: context, template: template, rule: rule)
            do {
                apply(draft, title: title, to: template, revision: revision.partialValue, at: now)
                rule.update(
                    recurrence: recurrence, timeOfDayMinutes: draft.timeOfDayMinutes, isEnabled: draft.isEnabled)
                // nil 是家长明确清空；不能用可空绑定跳过赋值、从而留下旧配置。
                rule.plannedTimeOfDayMinutes = draft.plannedTimeOfDayMinutes
                rule.deadlineTimeOfDayMinutes = draft.deadlineTimeOfDayMinutes
                try materializeAndSave(template, today: today, now: now)
                return template.id
            } catch {
                let restoresDeletedGraph = !context.deletedModelsArray.isEmpty
                detachInsertedOccurrences()
                original.restore()
                context.rollback()
                if restoresDeletedGraph {
                    // 17 撤回维护性删除时还会再次清空已载入逆关系缓存；删除标记撤回后
                    // 再恢复原图并清除恢复动作的脏标记，不进行任何补偿保存。
                    original.restore()
                    context.rollback()
                }
                throw error
            }
        }

        let template = TaskTemplate(
            title: title,
            iconName: draft.iconName,
            colorToken: draft.colorToken,
            targetDurationSeconds: TimeInterval(draft.targetDurationMinutes * 60),
            isEnabled: draft.isEnabled,
            createdAt: now,
            updatedAt: now,
            category: draft.category, timePeriod: draft.timePeriod, verificationType: draft.verificationType,
            xpReward: draft.xpReward, coinReward: draft.coinReward, activeBonusCoin: draft.activeBonusCoin
        )
        let recurrence = try TaskRecurrence.weekly(on: draft.weekdays, starting: today)
        let rule = ReminderRule(
            taskTemplateID: template.id,
            recurrence: recurrence,
            timeOfDayMinutes: draft.timeOfDayMinutes,
            isEnabled: draft.isEnabled,
            plannedTimeOfDayMinutes: draft.plannedTimeOfDayMinutes,
            deadlineTimeOfDayMinutes: draft.deadlineTimeOfDayMinutes
        )
        context.insert(template)
        context.insert(rule)
        // iPadOS 17 会在尚未入库模型的双向关系设置中触发陷阱；先确立同一 context 归属。
        template.reminderRule = rule
        rule.taskTemplate = template
        do {
            try materializeAndSave(template, today: today, now: now)
            return template.id
        } catch {
            // 先断本次新对象的逆关系，避免旧 runtime 的 Swift 层缓存留下孤儿图。
            detachInsertedOccurrences()
            template.reminderRule = nil
            rule.taskTemplate = nil
            context.rollback()
            throw error
        }
    }

    /// 仅暂存物化并执行唯一保存；失败由拥有原始图快照的外层新建/编辑分支恢复。
    private func materializeAndSave(
        _ template: TaskTemplate,
        today: LocalDate,
        now: Date
    ) throws {
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
        try saveChanges(context)
    }

    /// 事务开始时没有未保存模型，因此这些插入实例只可能来自本次物化。
    private func detachInsertedOccurrences() {
        for case let occurrence as TaskOccurrence in context.insertedModelsArray {
            occurrence.template = nil
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
        for value in [draft.plannedTimeOfDayMinutes, draft.deadlineTimeOfDayMinutes] {
            if let value, !(0..<24 * 60).contains(value) {
                throw TaskTemplateEditorError.invalidTime
            }
        }
        guard draft.xpReward >= 0, draft.coinReward >= 0, draft.activeBonusCoin >= 0 else {
            throw TaskTemplateEditorError.invalidReward
        }
        guard !draft.coinReward.addingReportingOverflow(draft.activeBonusCoin).overflow else {
            throw TaskTemplateEditorError.rewardOverflow
        }
    }

    private func apply(
        _ draft: TaskTemplateDraft,
        title: String,
        to template: TaskTemplate,
        revision: Int,
        at now: Date
    ) {
        template.title = title
        template.iconName = draft.iconName
        template.colorToken = draft.colorToken
        template.targetDurationSeconds = TimeInterval(draft.targetDurationMinutes * 60)
        template.isEnabled = draft.isEnabled
        template.categoryRawValue = draft.category.rawValue
        template.timePeriodRawValue = draft.timePeriod.rawValue
        template.verificationTypeRawValue = draft.verificationType.rawValue
        template.xpReward = draft.xpReward
        template.coinReward = draft.coinReward
        template.activeBonusCoin = draft.activeBonusCoin
        template.revision = revision
        template.updatedAt = now
    }
}
