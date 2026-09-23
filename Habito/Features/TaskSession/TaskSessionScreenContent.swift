import Foundation

/// 任务执行页可直接渲染的只读快照。
///
/// 数据库存储的是累计活动秒数和最后恢复时间，而不是每秒更新的数字。运行时展示只需在
/// 快照基础上补上 `now - snapshotAt`，因此锁屏或进入后台后不依赖计时器持续执行。
struct TaskSessionScreenContent: Equatable, Sendable {
    enum PrimaryAction: Equatable, Sendable {
        case start
        case pause
        case resume
        case none
    }

    let task: KidTaskNavigationItem
    let targetDurationSeconds: TimeInterval
    let activeSessionState: TimerSessionState?
    let activeDurationAtSnapshot: TimeInterval
    let snapshotAt: Date

    var primaryAction: PrimaryAction {
        switch (task.status, activeSessionState) {
        case (.pending, nil):
            .start
        case (.inProgress, .running):
            .pause
        case (.inProgress, .paused):
            .resume
        default:
            .none
        }
    }

    var isRunning: Bool {
        activeSessionState == .running
    }

    /// 目标进度只用于视觉提示；超过目标后保持满格，但计时仍继续累计。
    func progress(at now: Date) -> Double {
        min(1, displayedActiveDuration(at: now) / targetDurationSeconds)
    }

    /// 返回指定时刻应显示的活动秒数。
    ///
    /// - Note: 设备墙上时钟若被向后调整，当前运行段暂时冻结为快照值，避免界面显示负数；
    ///   下一次场景激活会重新从持久化时间戳校验并加载。
    func displayedActiveDuration(at now: Date) -> TimeInterval {
        guard isRunning else { return activeDurationAtSnapshot }
        return activeDurationAtSnapshot + max(0, now.timeIntervalSince(snapshotAt))
    }
}
