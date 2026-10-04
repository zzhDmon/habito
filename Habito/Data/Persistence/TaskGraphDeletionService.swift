import Foundation
import SwiftData

/// 将任务对象图的维护性物理删除集中到同一个主 actor/context。
///
/// iPadOS 17 的级联删除在回归中留下拥有记录，因此显式按稳定外键清理，不只依赖关系缓存。
/// 本服务不决定哪些实例允许删除；历史/进行中/单日覆盖保护仍由调用用例判断。
@MainActor
struct TaskGraphDeletionService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 清理实例拥有的完成、计时与通知映射，再暂存实例删除。
    ///
    /// - Parameter occurrence: 调用方已判定可物理删除、且属于该 context 的实例。
    /// - Throws: 对象不属于本 context 或读取拥有记录失败时抛错；完整读取前不修改对象图。
    /// - Important: 不调用 `save()`，由外层事务统一保存/回滚并触发通知重建。
    ///   映射删除不会直接操作系统通知；系统残留仍通过稳定 identifier 核对清理。
    func stageOccurrenceDeletion(_ occurrence: TaskOccurrence) throws {
        guard occurrence.modelContext === context else { throw TaskGraphDeletionError.modelNotInContext }
        let occurrenceID = occurrence.id
        let completions = try context.fetch(
            FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.occurrenceID == occurrenceID })
        )
        let sessions = try context.fetch(
            FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == occurrenceID })
        )
        let links = try context.fetch(
            FetchDescriptor<NotificationLink>(predicate: #Predicate { $0.occurrenceID == occurrenceID })
        )

        // 先断开关系，避免旧 runtime 在删除父对象时重复注册已删除的子对象。
        occurrence.completionRecord = nil
        occurrence.timerSessions = []
        occurrence.notificationLinks = []
        for record in completions {
            record.occurrence = nil
            context.delete(record)
        }
        for session in sessions {
            session.occurrence = nil
            context.delete(session)
        }
        for link in links {
            link.occurrence = nil
            context.delete(link)
        }
        occurrence.template = nil
        context.delete(occurrence)
    }

    /// 删除模板与规则，但把历史实例保留为仅依赖自身快照的记录。
    ///
    /// - Parameter template: 维护工具已明确授权物理删除的模板；常规 UI 仍使用软删除。
    /// - Throws: 对象不属于本 context 或读取规则/实例失败时抛错，尚未变更对象图。
    /// - Important: 不保存、不删除任何实例，不改实例的 `templateID` 和历史快照。
    func stageTemplateDeletionPreservingHistory(_ template: TaskTemplate) throws {
        guard template.modelContext === context else { throw TaskGraphDeletionError.modelNotInContext }
        let templateID = template.id
        let rules = try context.fetch(
            FetchDescriptor<ReminderRule>(predicate: #Predicate { $0.taskTemplateID == templateID })
        )
        let occurrences = try context.fetch(
            FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.templateID == templateID })
        )
        template.reminderRule = nil
        for rule in rules {
            rule.taskTemplate = nil
            context.delete(rule)
        }
        for occurrence in occurrences {
            occurrence.template = nil
        }
        template.occurrences = []
        context.delete(template)
    }
}
