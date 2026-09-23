import Foundation

/// 一次今日查询的稳定结果和进度摘要。
struct TodayTasksSnapshot: Equatable, Sendable {
    let date: LocalDate
    let isCurrentDate: Bool
    let tasks: [TodayTaskItem]
    let recommendedTaskID: UUID?
    let completedCount: Int
    let totalCount: Int

    /// 被家长跳过的实例不进入孩子的任务总数。
    var visibleTasks: [TodayTaskItem] {
        tasks.filter { $0.status != .skipped }
    }

    var isEmpty: Bool {
        totalCount == 0
    }

    var isAllCompleted: Bool {
        totalCount > 0 && completedCount == totalCount
    }
}
