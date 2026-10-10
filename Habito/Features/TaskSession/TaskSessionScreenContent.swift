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
    let completion: TodayTaskCompletion?
    let submission: TaskSubmissionSnapshot?
    let verificationType: TaskVerificationType

    init(
        task: KidTaskNavigationItem, targetDurationSeconds: TimeInterval, activeSessionState: TimerSessionState?,
        activeDurationAtSnapshot: TimeInterval, snapshotAt: Date, completion: TodayTaskCompletion?,
        submission: TaskSubmissionSnapshot? = nil, verificationType: TaskVerificationType = .selfConfirm
    ) {
        self.task = task
        self.targetDurationSeconds = targetDurationSeconds
        self.activeSessionState = activeSessionState
        self.activeDurationAtSnapshot = activeDurationAtSnapshot
        self.snapshotAt = snapshotAt
        self.completion = completion
        self.submission = submission
        self.verificationType = verificationType
    }

    /// 等待是审计快照的派生值，不用仍为 pending 的旧状态开放操作。
    var isAwaitingReview: Bool { submission?.state == .waiting }

    var primaryAction: PrimaryAction {
        guard !isAwaitingReview else { return .none }
        return switch (task.status, activeSessionState) {
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

    var canComplete: Bool {
        !isAwaitingReview && (task.status == .pending || task.status == .inProgress)
    }

    /// 孩子侧撤销窗口以持久化完成时间为起点，页面重建不会重置倒计时。
    func canUndoCompletion(at now: Date) -> Bool {
        guard !isAwaitingReview, task.status == .completed, let completion else { return false }
        return CompletionUndoPolicy.canUndo(completedAt: completion.completedAt, now: now)
    }

    /// 返回撤销按钮应显示的剩余整秒数，窗口外固定为零。
    func undoRemainingSeconds(at now: Date) -> Int {
        guard canUndoCompletion(at: now), let completion else { return 0 }
        let deadline = completion.completedAt.addingTimeInterval(CompletionUndoPolicy.window)
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    /// 目标进度只用于视觉提示；超过目标后保持满格，但计时仍继续累计。
    func progress(at now: Date) -> Double {
        min(1, displayedActiveDuration(at: now) / targetDurationSeconds)
    }

    /// 只提供显示建议，目标达成不触发完成、奖励或审核；暂停时剩余量保持不变。
    func remainingTargetDuration(at now: Date) -> TimeInterval {
        max(0, targetDurationSeconds - displayedActiveDuration(at: now))
    }

    func hasReachedGoal(at now: Date) -> Bool {
        remainingTargetDuration(at: now) == 0
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
