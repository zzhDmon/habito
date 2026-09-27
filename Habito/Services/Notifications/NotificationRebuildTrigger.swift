import Observation

/// 汇聚业务写事件，让根视图通过结构化任务执行统一通知重建。
@MainActor
@Observable
final class NotificationRebuildTrigger {
    private(set) var revision = 0

    /// 业务数据成功落盘后调用；连续事件只表达“需要按最新真相重建”，不携带旧快照。
    func requestRebuild() {
        revision &+= 1
    }
}
