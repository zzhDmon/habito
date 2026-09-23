import Foundation

/// 家长执行停用、启用或软删除前可确认的实例影响摘要。
struct TaskTemplateLifecycleImpact: Equatable, Sendable {
    let templateID: UUID
    let title: String
    let action: TaskTemplateLifecycleAction
    let removableOccurrenceCount: Int
    let preservedOccurrenceCount: Int
    let latestOccurrenceDate: LocalDate?
}
