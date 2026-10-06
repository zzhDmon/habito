/// 今日剩余任务的不可变展示投影，不持有 SwiftData 模型或财务状态。
///
/// 投影与已有导航值的相等性遵循都归属主 actor，不为纯展示运算突破 UI 隔离边界。
@MainActor
struct TodayTaskGroup: Equatable, Identifiable, Sendable {
    let id: TodayTaskGroupKind
    let tasks: [KidTaskNavigationItem]

    /// 按明确时段分组，保留每组原有查询顺序；输入已由今日用例排除推荐和跳过项。
    ///
    /// - Parameter tasks: 现有推荐排序后的剩余导航值，不重新按提醒钟点排序。
    /// - Returns: 非空且身份稳定的展示组；跨日项只出现于跨日组，不再出现在其时段组。
    static func makeGroups(from tasks: [KidTaskNavigationItem]) -> [Self] {
        TodayTaskGroupKind.displayOrder.compactMap { kind in
            let items = tasks.filter { task in
                let taskKind: TodayTaskGroupKind = task.isCarryOver ? .carryOver : .timePeriod(task.timePeriod)
                return taskKind == kind
            }
            return items.isEmpty ? nil : Self(id: kind, tasks: items)
        }
    }
}
