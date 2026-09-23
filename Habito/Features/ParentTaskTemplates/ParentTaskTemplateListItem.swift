import Foundation

/// 家长模板列表使用的稳定只读值，不直接暴露可变 SwiftData 模型。
struct ParentTaskTemplateListItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let iconName: String
    let targetDurationSeconds: TimeInterval
    let lifecycleState: TaskTemplateLifecycleState
    let nextScheduledAt: Date?
    let updatedAt: Date
}
