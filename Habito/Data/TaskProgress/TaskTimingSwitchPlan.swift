import Foundation

/// 确认前的只读事实，保持稳定ID而不把SwiftData活对象传入弹窗。
struct TaskTimingSwitchPlan: Equatable, Sendable {
    let target: TodayTaskItem
    let runningTasks: [TodayTaskItem]

    var runningIDs: Set<UUID> { Set(runningTasks.map(\.id)) }
}
