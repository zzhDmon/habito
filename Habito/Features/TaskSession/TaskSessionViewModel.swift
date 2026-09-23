import Foundation
import Observation
import OSLog
import SwiftData

/// 协调任务执行页查询与计时写入，避免 View 直接编排 SwiftData 事务。
@MainActor
@Observable
final class TaskSessionViewModel {
    private(set) var state: TaskSessionViewState = .loading

    private let occurrenceID: UUID
    private let context: ModelContext
    private let queryService: TodayTaskQueryService
    private let progressService: TaskProgressService
    private let dateProvider: any DateProviding
    private var calendar: Calendar
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "TaskSession")

    init(
        occurrenceID: UUID,
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding
    ) {
        self.occurrenceID = occurrenceID
        self.context = context
        queryService = TodayTaskQueryService(
            context: context,
            calendar: calendar,
            timeZone: timeZone
        )
        progressService = TaskProgressService(context: context)
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.calendar.timeZone = timeZone
    }

    /// 首次进入页面时加载稳定实例 ID 对应的最新状态。
    func load() {
        reload(showLoading: true)
    }

    /// App 回到前台或操作完成后静默刷新，避免已有内容短暂闪回加载页。
    func refresh() {
        reload(showLoading: false)
    }

    /// 根据当前页面状态执行开始或继续；运行中重复触发不会创建第二个会话。
    func startOrResume() {
        guard case let .loaded(content) = state else { return }

        do {
            let occurrence = try fetchOccurrence()
            let now = dateProvider.now()
            switch content.primaryAction {
            case .start:
                try progressService.startTiming(for: occurrence, at: now)
            case .resume:
                try progressService.resumeTiming(for: occurrence, at: now)
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
            try progressService.pauseTiming(for: fetchOccurrence(), at: dateProvider.now())
            reload(showLoading: false)
        } catch {
            handle(error)
        }
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
                    snapshotAt: now
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
