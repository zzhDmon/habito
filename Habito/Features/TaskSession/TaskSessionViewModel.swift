import Foundation
import Observation
import OSLog
import SwiftData

/// 协调任务执行页查询与计时写入，避免 View 直接编排 SwiftData 事务。
@MainActor
@Observable
final class TaskSessionViewModel {
    private(set) var state: TaskSessionViewState = .loading
    private(set) var snoozeState: TaskSnoozeState = .idle
    private(set) var actionFailure: TaskSessionActionFailure?
    var isActionErrorPresented = false

    private let occurrenceID: UUID
    private let context: ModelContext
    private let queryService: TodayTaskQueryService
    private let progressService: TaskProgressService
    private let completionService: TaskCompletionService
    private let undoService: TaskCompletionUndoService
    private let dateProvider: any DateProviding
    private let snoozeService: TaskSnoozeService?
    private let notificationRebuildTrigger: NotificationRebuildTrigger
    private var calendar: Calendar
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "TaskSession")

    init(
        occurrenceID: UUID,
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding,
        snoozeService: TaskSnoozeService? = nil,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger(),
        completionService: TaskCompletionService? = nil,
        undoService: TaskCompletionUndoService? = nil
    ) {
        self.occurrenceID = occurrenceID
        self.context = context
        queryService = TodayTaskQueryService(
            context: context,
            calendar: calendar,
            timeZone: timeZone
        )
        progressService = TaskProgressService(context: context)
        self.completionService = completionService ?? TaskCompletionService(context: context)
        self.undoService = undoService ?? TaskCompletionUndoService(context: context)
        self.dateProvider = dateProvider
        self.snoozeService = snoozeService
        self.notificationRebuildTrigger = notificationRebuildTrigger
        self.calendar = calendar
        self.calendar.timeZone = timeZone
    }

    /// 为当前未完成任务安排唯一的十分钟稍后提醒，并把业务失败转换为儿童可理解反馈。
    func snooze() async {
        guard snoozeState != .scheduling else { return }
        guard case let .loaded(content) = state, content.canComplete else { return }
        guard let snoozeService else {
            snoozeState = .failed
            return
        }

        snoozeState = .scheduling
        // 失败补偿也可能需要重建；只要尝试过系统操作，就让根视图按最终真相核对。
        defer { notificationRebuildTrigger.requestRebuild() }
        do {
            let scheduledAt = try await snoozeService.schedule(
                occurrenceID: occurrenceID,
                at: dateProvider.now()
            )
            snoozeState = .scheduled(scheduledAt)
        } catch is CancellationError {
            snoozeState = .idle
        } catch TaskSnoozeError.crossesLocalMidnight {
            snoozeState = .crossesMidnight
        } catch TaskSnoozeError.pendingLimitReached {
            snoozeState = .budgetFull
        } catch TaskSnoozeError.notificationsUnavailable {
            snoozeState = .notificationsDisabled
        } catch is TaskSnoozeError {
            snoozeState = .unavailable
        } catch {
            logger.error("稍后提醒创建失败：\(String(describing: type(of: error)), privacy: .public)")
            snoozeState = .failed
        }
    }

    /// 首次进入页面时加载稳定实例 ID 对应的最新状态。
    func load() {
        reload(showLoading: true)
    }

    /// App 回到前台或操作完成后静默刷新，避免已有内容短暂闪回加载页。
    func refresh() {
        reload(showLoading: false)
    }

    /// 提供显示层的业务时刻；TimelineView 只负责刷新节奏，不能另用系统时间计算撤销窗口。
    ///
    /// - Returns: 与开始、完成和撤销写入共用的注入时钟，避免测试或未来时钟替换时显示与操作不同步。
    func currentDate() -> Date {
        dateProvider.now()
    }

    /// 根据当前页面状态执行开始或继续；运行中重复触发不会创建第二个会话。
    func startOrResume() {
        guard case let .loaded(content) = state else { return }

        do {
            let occurrence = try fetchOccurrence()
            let now = dateProvider.now()
            switch content.primaryAction {
            case .start:
                _ = try progressService.startTiming(for: occurrence, at: now)
                // 主提醒只属于待处理实例；开始成功后立即核对，避免尚未到点的旧主提醒继续出现。
                notificationRebuildTrigger.requestRebuild()
            case .resume:
                _ = try progressService.resumeTiming(for: occurrence, at: now)
            case .pause, .none:
                return
            }
            reload(showLoading: false)
        } catch {
            handle(error)
        }
    }

    /// 暂停当前运行段；累计秒数在事务内一次性落盘。
    func pause() {
        guard case let .loaded(content) = state, content.primaryAction == .pause else { return }

        do {
            _ = try progressService.pauseTiming(for: fetchOccurrence(), at: dateProvider.now())
            reload(showLoading: false)
        } catch {
            handle(error)
        }
    }

    /// 由孩子手动完成，计时、事实和奖励同一次保存，成功后才重建通知。
    func completeTask() {
        guard case let .loaded(content) = state, content.canComplete else { return }

        do {
            let result = try completionService.complete(
                fetchOccurrence(),
                at: dateProvider.now(),
                source: .childManual
            )
            if result.didComplete { notificationRebuildTrigger.requestRebuild() }
            snoozeState = .idle
            clearActionFailure()
            reload(showLoading: false)
        } catch {
            handleActionFailure(error)
        }
    }

    /// 在完成时间后的 5 秒窗口内撤销；过期操作只刷新页面，不改写完成事实。
    func undoCompletion() {
        guard case let .loaded(content) = state else { return }
        let now = dateProvider.now()
        guard content.canUndoCompletion(at: now), let completion = content.completion else {
            reload(showLoading: false)
            return
        }

        do {
            let result = try undoService.undo(fetchOccurrence(), completionID: completion.id, at: now)
            if result.didUndo { notificationRebuildTrigger.requestRebuild() }
            clearActionFailure()
            reload(showLoading: false)
        } catch {
            handleActionFailure(error)
        }
    }

    private func clearActionFailure() {
        actionFailure = nil
        isActionErrorPresented = false
    }

    private func handleActionFailure(_ error: Error) {
        logger.error("完成或撤销失败：\(String(describing: type(of: error)), privacy: .public)")
        if case RewardLedgerError.insufficientCoins = error {
            actionFailure = .insufficientCoins
        } else if error is TaskCompletionServiceError || error is TaskCompletionUndoError
            || error is TaskProgressServiceError || error is TaskSessionViewModelError || error is RewardLedgerError
        {
            actionFailure = .unavailable
        } else {
            actionFailure = .saveFailed
        }
        // 事务已保证失败不半写入，保留原页面事实，不能把已完成误显示成丢失。
        isActionErrorPresented = true
    }

    private func reload(showLoading: Bool) {
        if showLoading { state = .loading }
        do {
            let now = dateProvider.now()
            let item = try queryService.item(id: occurrenceID, at: now)
            state = .loaded(
                TaskSessionScreenContent(
                    task: KidTaskNavigationItem(item: item, calendar: calendar),
                    targetDurationSeconds: item.targetDurationSeconds,
                    activeSessionState: item.activeSessionState,
                    activeDurationAtSnapshot: item.activeDurationSeconds,
                    snapshotAt: now,
                    completion: item.completion
                )
            )
        } catch {
            handle(error)
        }
    }

    private func fetchOccurrence() throws -> TaskOccurrence {
        let id = occurrenceID
        let descriptor = FetchDescriptor<TaskOccurrence>(
            predicate: #Predicate { $0.id == id }
        )
        guard let occurrence = try context.fetch(descriptor).first else {
            throw TaskSessionViewModelError.occurrenceNotFound(occurrenceID: id)
        }
        return occurrence
    }

    private func handle(_ error: Error) {
        logger.error("任务执行页操作失败：\(String(describing: type(of: error)), privacy: .public)")
        state = .failed
    }
}
