import Foundation
import Observation
import OSLog
import SwiftData

/// 驱动孩子今日页的可观察状态，并隔离查询与展示格式化逻辑。
@MainActor
@Observable
final class TodayViewModel {
    private(set) var state: TodayViewState = .loading
    private(set) var rewardState: TodayRewardState = .loading

    private let context: ModelContext
    private let queryService: TodayTaskQueryService
    private let rewardLedger: RewardLedgerService
    private let dateProvider: any DateProviding
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "Today")

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding
    ) {
        self.context = context
        rewardLedger = RewardLedgerService(context: context)
        queryService = TodayTaskQueryService(
            context: context,
            calendar: calendar,
            timeZone: timeZone
        )
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.timeZone = timeZone
        self.calendar.timeZone = timeZone
    }

    /// 重新读取今天的实例。失败时保留明确页面状态，并记录不含孩子隐私的错误类型。
    func load() {
        state = .loading
        do {
            let now = dateProvider.now()
            let date = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
            let snapshot = try queryService.snapshot(for: date, at: now)
            state = .loaded(makeContent(from: snapshot))
        } catch {
            logger.error("今日任务加载失败：\(String(describing: type(of: error)), privacy: .public)")
            state = .failed
        }
        // 两类查询独立失败；孩子不能因资产故障失去任务，也不能因任务损坏得到假余额。
        loadRewards()
    }

    /// 显式刷新已保存账本的真实资产，不发奖、不消费，也不保存或回滚家长的其他编辑。
    ///
    /// - Important: 与任务加载同步归属主 actor，校验到读取之间不让出执行。
    ///   未保存上下文可能含暂存交易；不能将其展示为到账，失败后移除旧余额等待重试。
    func loadRewards() {
        rewardState = .loading
        do {
            guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
            rewardState = .loaded(try rewardLedger.balance())
        } catch {
            logger.error("儿童资产加载失败：\(String(describing: type(of: error)), privacy: .public)")
            rewardState = .failed
        }
    }

    private func makeContent(from snapshot: TodayTasksSnapshot) -> TodayScreenContent {
        let tasks = snapshot.visibleTasks.map { item in
            KidTaskNavigationItem(item: item, calendar: calendar, referenceDate: snapshot.date)
        }
        let recommendedTask = tasks.first { $0.id == snapshot.recommendedTaskID }
        let remainingTasks = tasks.filter { $0.id != snapshot.recommendedTaskID }

        return TodayScreenContent(
            recommendedTask: recommendedTask,
            remainingTasks: remainingTasks,
            completedCount: snapshot.completedCount,
            totalCount: snapshot.totalCount,
            isAllCompleted: snapshot.isAllCompleted
        )
    }
}
