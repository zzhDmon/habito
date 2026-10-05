/// 待验收队列的纯值加载状态；空数组才是合法空态，失败不可降级为空。
nonisolated enum ParentReviewViewState: Equatable, Sendable {
    case loading
    case loaded([ParentReviewQueueItem])
    case failed
}
