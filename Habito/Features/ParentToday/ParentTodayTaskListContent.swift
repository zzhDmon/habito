/// 家长今日实例页使用的不可变页面值。
struct ParentTodayTaskListContent: Equatable, Sendable {
    let date: LocalDate
    let items: [TodayTaskItem]
}
