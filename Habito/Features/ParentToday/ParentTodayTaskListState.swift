/// 家长今日实例页的完整加载状态。
enum ParentTodayTaskListState: Equatable {
    case loading
    case loaded(ParentTodayTaskListContent)
    case failed
}
