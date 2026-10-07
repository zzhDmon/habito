/// 今日全部确认完成的只读结果，不代表新的完成事件或奖励收据。
///
/// 查询层的 `isAllCompleted` 已排除待验收和未完成跨日任务；这里同时防御空分母与矛盾计数。
/// 不读取时间、不写已读状态或账本，因此刷新与重启只会重新展示同一结果。
struct TodayCompletionSummary: Equatable, Sendable {
    let completedCount: Int

    /// 仅可信查询的全完成状态和正数一致计数可以生成完成印章。
    ///
    /// - Parameters:
    ///   - completedCount: 今日已确认完成数，跳过和跨日任务不计入。
    ///   - totalCount: 今日有效任务数；零意味着无任务，不能解读为全部完成。
    ///   - isAllCompleted: 原今日查询的完整状态，不能仅由百分比反推。
    /// - Note: 没有奖励字段；零奖励也可以肯定完成事实，不能在界面补发货币。
    init?(completedCount: Int, totalCount: Int, isAllCompleted: Bool) {
        guard isAllCompleted, totalCount > 0, completedCount == totalCount else { return nil }
        self.completedCount = completedCount
    }
}
