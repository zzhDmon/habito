import Foundation

/// 一次今日查询的稳定结果和进度摘要。
struct TodayTasksSnapshot: Equatable, Sendable {
    let date: LocalDate
    let isCurrentDate: Bool
    let tasks: [TodayTaskItem]
    let carryOverTasks: [TodayTaskItem]
    let recommendedTaskID: UUID?
    let completedCount: Int
    let totalCount: Int

    /// 被家长跳过的实例不进入孩子的任务总数。
    var visibleTasks: [TodayTaskItem] {
        carryOverTasks + tasks.filter { $0.status != .skipped && $0.status != .cancelled }
    }

    var isEmpty: Bool {
        visibleTasks.isEmpty
    }

    var isAllCompleted: Bool {
        carryOverTasks.isEmpty && totalCount > 0 && completedCount == totalCount
    }
}
