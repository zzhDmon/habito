/// 今日页加载状态；错误细节只写入诊断日志，孩子界面展示可重试提示。
enum TodayViewState: Equatable, Sendable {
    case loading
    case loaded(TodayScreenContent)
    case failed
}
