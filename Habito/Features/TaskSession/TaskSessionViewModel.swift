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
    private(set) var completionFeedback: TaskSessionCompletionFeedback?
    var isActionErrorPresented = false
    var isTimingSwitchPresented = false
    private(set) var pendingTimingSwitch: TaskTimingSwitchPlan?

    private let occurrenceID: UUID
    private let context: ModelContext
    private let queryService: TodayTaskQueryService
    private let progressService: TaskProgressService
    private let timingSwitchService: TaskTimingSwitchService
    private let completionService: TaskCompletionService
    private let submissionService: TaskSubmissionService
    private let undoService: TaskCompletionUndoService
    private let dateProvider: any DateProviding
    private let snoozeService: TaskSnoozeService?
    private let notificationRebuildTrigger: NotificationRebuildTrigger
    private let onCompletionSaved: (@MainActor (TaskCompletionResult) -> Void)?
    private let onCompletionChanged: (@MainActor () -> Void)?
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
        undoService: TaskCompletionUndoService? = nil,
        submissionService: TaskSubmissionService? = nil,
        timingSwitchService: TaskTimingSwitchService? = nil,
        onCompletionSaved: (@MainActor (TaskCompletionResult) -> Void)? = nil,
        onCompletionChanged: (@MainActor () -> Void)? = nil
    ) {
        self.occurrenceID = occurrenceID
        self.context = context
        queryService = TodayTaskQueryService(
            context: context,
            calendar: calendar,
            timeZone: timeZone
        )
        progressService = TaskProgressService(context: context)
        self.timingSwitchService =
            timingSwitchService ?? TaskTimingSwitchService(context: context, calendar: calendar, timeZone: timeZone)
        self.completionService = completionService ?? TaskCompletionService(context: context)
        self.submissionService = submissionService ?? TaskSubmissionService(context: context)
        self.undoService = undoService ?? TaskCompletionUndoService(context: context)
        self.dateProvider = dateProvider
        self.snoozeService = snoozeService
        self.notificationRebuildTrigger = notificationRebuildTrigger
        self.onCompletionSaved = onCompletionSaved
        self.onCompletionChanged = onCompletionChanged
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

    /// 时间展示和计时共享注入时钟，但不会改变完成权限、通知或奖励事实。
    func makeTimingPresentation(for task: KidTaskNavigationItem) -> KidTaskTimingPresentation {
        KidTaskTimingPresentation(task: task, at: dateProvider.now())
    }

    /// 根据当前页面状态执行开始或继续；运行中重复触发不会创建第二个会话。
    func startOrResume() {
        guard case let .loaded(content) = state, content.primaryAction == .start || content.primaryAction == .resume
        else { return }
        do {
            let plan = try timingSwitchService.plan(for: occurrenceID, at: dateProvider.now())
            if !plan.runningTasks.isEmpty {
                pendingTimingSwitch = plan
                isTimingSwitchPresented = true
                return
            }
            performTimingStart(confirmedRunningIDs: [])
        } catch {
            // 删除后旧页面已没有有效任务事实，必须进入错误态；普通事务失败才保留页面。
            if case TodayTaskQueryError.occurrenceNotFound = error { handle(error) } else { handleActionFailure(error) }
        }
    }

    /// 弹窗文案来自预检快照；实际写入仍必须重新核对运行集合。
    var timingSwitchMessage: String {
        guard let plan = pendingTimingSwitch else { return "" }
        let names = plan.runningTasks.map(\.title).joined(separator: "、")
        if plan.runningTasks.count == 1 {
            return String.localizedStringWithFormat(
                String(localized: "taskSession.switchMessage"), names, names, plan.target.title)
        }
        return String.localizedStringWithFormat(
            String(localized: "taskSession.switchMultipleMessage"), names, plan.target.title)
    }

    /// 明确确认才暂停其他任务；失败保留执行页并反馈，不出现半完成切换。
    func confirmTimingSwitch() {
        guard let plan = pendingTimingSwitch else { return }
        clearTimingSwitch()
        performTimingStart(confirmedRunningIDs: plan.runningIDs)
    }

    /// 取消不写计时；从最新事实选择仍在运行的任务，防止跳到已经完成的旧快照。
    func continueCurrentTask() -> UUID? {
        clearTimingSwitch()
        do {
            return try timingSwitchService.plan(for: occurrenceID, at: dateProvider.now()).runningTasks.first?.id
        } catch {
            refresh()
            handleActionFailure(error)
            return nil
        }
    }

    private func clearTimingSwitch() {
        isTimingSwitchPresented = false
        pendingTimingSwitch = nil
    }

    private func performTimingStart(confirmedRunningIDs: Set<UUID>) {
        let wasPending = if case let .loaded(content) = state { content.primaryAction == .start } else { false }
        do {
            _ = try timingSwitchService.start(
                for: occurrenceID, at: dateProvider.now(), confirmedRunningIDs: confirmedRunningIDs)
            if wasPending { notificationRebuildTrigger.requestRebuild() }
            clearActionFailure()
            refresh()
        } catch {
            if error as? TaskTimingSwitchError == .runningTasksChanged {
                refresh()
                actionFailure = .timingChanged
                isActionErrorPresented = true
            } else {
                handleActionFailure(error)
            }
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

    /// 重新读取实例验收方式路由事务；提交只等待，自行确认才真正完成并结算。
    ///
    /// 保存成功且确为新事件才发布反馈/通知；旧页面或幂等重试不能重复庆祝。
    func completeTask() {
        guard case let .loaded(content) = state, content.canComplete else { return }

        do {
            let occurrence = try fetchOccurrence()
            let latestSubmission = try TaskSubmissionHistory(context: context).latest(for: occurrence)
            if latestSubmission?.reviewState == .waiting {
                // 另一页面已经提交；沿用幂等原收据，不因后来验收配置变化误走自行完成。
                _ = try submissionService.submit(occurrence, at: dateProvider.now())
                snoozeState = .idle
                clearActionFailure()
                reload(showLoading: false)
                return
            }
            if occurrence.status == .completed {
                // 家长/另一页面已确认完成时只刷新，不能对当前完成再创建一次提交或奖励反馈。
                clearActionFailure()
                reload(showLoading: false)
                return
            }
            guard let verification = occurrence.verificationTypeSnapshot else {
                throw TaskCompletionServiceError.invalidConfiguration(occurrence.id)
            }
            switch verification {
            case .selfConfirm:
                let result = try completionService.complete(occurrence, at: dateProvider.now(), source: .childManual)
                if result.didComplete {
                    completionFeedback = .completed(result)
                    notificationRebuildTrigger.requestRebuild()
                    // 非抛错回调发生在save成功之后；附加仪式读取失败不能变成打卡失败。
                    onCompletionSaved?(result)
                }
            case .parentApproval:
                let result = try submissionService.submit(occurrence, at: dateProvider.now())
                if result.didSubmit {
                    completionFeedback = .submitted(result)
                    notificationRebuildTrigger.requestRebuild()
                }
            }
            snoozeState = .idle
            clearActionFailure()
            reload(showLoading: false)
        } catch {
            handleActionFailure(error)
        }
    }

    /// 显示层消费或孩子关闭反馈后清空；以后刷新/重复调用不能用历史记录重播。
    func dismissCompletionFeedback() {
        completionFeedback = nil
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
            if result.didUndo {
                notificationRebuildTrigger.requestRebuild()
                onCompletionChanged?()
            }
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
            || error is TaskSubmissionError || error is TaskTimingSwitchError || error is TodayTaskQueryError
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
            reconcileFeedback(with: item)
            state = .loaded(
                TaskSessionScreenContent(
                    task: KidTaskNavigationItem(
                        item: item, calendar: calendar,
                        referenceDate: try LocalDate(date: now, calendar: calendar, timeZone: calendar.timeZone)),
                    targetDurationSeconds: item.targetDurationSeconds,
                    activeSessionState: item.activeSessionState,
                    activeDurationAtSnapshot: item.activeDurationSeconds,
                    snapshotAt: now,
                    completion: item.completion,
                    submission: item.submission,
                    verificationType: item.verificationType
                )
            )
        } catch {
            handle(error)
        }
    }

    /// 原提交被审核/退回或原完成被撤销时，不在页面上保留已经过期的结果反馈。
    private func reconcileFeedback(with item: TodayTaskItem) {
        switch completionFeedback {
        case let .submitted(result):
            if !item.isAwaitingReview || item.submission?.id != result.submissionID { completionFeedback = nil }
        case let .completed(result):
            if item.completion?.id != result.completionID { completionFeedback = nil }
        case nil: break
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
