import Foundation
import SwiftData

/// 在主 actor 的单个事务内取消未开始任务，保留唯一键以抑制规则重建。
///
/// 这里不直接调用系统通知。调用方仅在保存成功后请求统一通知重建，失败时原提醒仍有效。
@MainActor
struct TaskDeletionService {
    let context: ModelContext
    private let saveChanges: @MainActor () throws -> Void

    init(context: ModelContext, saveChanges: (@MainActor () throws -> Void)? = nil) {
        self.context = context
        self.saveChanges = saveChanges ?? { try context.save() }
    }

    /// 即使状态回到 pending，计时、提交或撤销完成的历史也不能当成“从未开始”。
    static func canDelete(_ occurrence: TaskOccurrence, context: ModelContext) throws -> Bool {
        guard occurrence.status == .pending || occurrence.status == .skipped else { return false }
        let id = occurrence.id
        let sessions = try context.fetchCount(
            FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == id }))
        let completions = try context.fetchCount(
            FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.occurrenceID == id }))
        let submissions = try context.fetchCount(
            FetchDescriptor<TaskSubmission>(predicate: #Predicate { $0.occurrenceID == id }))
        return sessions == 0 && completions == 0 && submissions == 0
    }

    /// 确认后重新检查状态，避免陈旧页面删除已经开始的任务。
    /// - Parameters:
    ///   - occurrenceID: 用户选中的稳定任务实例标识。
    ///   - scope: 本次取消或整个重复任务；一次性规则不接受周期范围。
    ///   - today: 注入业务日历计算的今天；更早日期始终保留。
    ///   - now: 注入时钟的保存时刻。
    /// - Throws: 脏上下文、过期操作或保存失败；不会回滚调用方的未保存编辑。
    func delete(occurrenceID: UUID, scope: TaskDeletionScope, today: LocalDate, now: Date) throws {
        guard !context.hasChanges else { throw TaskDeletionError.pendingChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw TaskDeletionError.invalidTime }
        guard
            let selected = try context.fetch(
                FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == occurrenceID })
            ).first,
            try LocalDate(dateKey: selected.dateKey) >= today,
            try Self.canDelete(selected, context: context),
            let template = selected.template, let rule = template.reminderRule
        else { throw TaskDeletionError.unavailable }
        if scope == .series, try rule.decodedRecurrence().kind != .weekly { throw TaskDeletionError.notRecurring }
        let nextRevision = template.revision.addingReportingOverflow(1)
        if scope == .series, nextRevision.overflow { throw TaskDeletionError.revisionOverflow }

        let templateID = template.id
        let candidates =
            scope == .occurrence
            ? [selected]
            : try context.fetch(
                FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.templateID == templateID }))
        var targets: [TaskOccurrence] = []
        for occurrence in candidates {
            let date = try LocalDate(dateKey: occurrence.dateKey)
            guard occurrence.status != nil else { throw TaskDeletionError.unavailable }
            if date >= today, try Self.canDelete(occurrence, context: context) { targets.append(occurrence) }
        }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        // iPadOS 17 rollback 不总能恢复被页面持有的标量缓存，因此先恢复精确旧值，再回滚事务。
        let oldRows = targets.map { ($0, $0.statusRawValue, $0.updatedAt) }
        let oldTemplate = (
            template.isEnabled, template.archivedAt, template.revision, template.updatedAt, rule.isEnabled
        )
        for occurrence in targets {
            occurrence.statusRawValue = TaskOccurrenceStatus.cancelled.rawValue
            occurrence.updatedAt = now
        }
        if scope == .series {
            template.isEnabled = false
            template.archivedAt = now
            template.revision = nextRevision.partialValue
            template.updatedAt = now
            rule.isEnabled = false
        }
        do {
            try saveChanges()
        } catch {
            for (row, status, updatedAt) in oldRows { row.statusRawValue = status; row.updatedAt = updatedAt }
            template.isEnabled = oldTemplate.0
            template.archivedAt = oldTemplate.1
            template.revision = oldTemplate.2
            template.updatedAt = oldTemplate.3
            rule.isEnabled = oldTemplate.4
            context.rollback()
            throw error
        }
    }
}
