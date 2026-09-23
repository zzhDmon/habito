/// 任务执行页状态。失败原因只进入诊断日志，孩子界面提供简短重试入口。
enum TaskSessionViewState: Equatable, Sendable {
    case loading
    case loaded(TaskSessionScreenContent)
    case failed
}
