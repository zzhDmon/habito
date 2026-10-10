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
    private(set) var dailyRewardState: TodayDailyRewardState = .loading
    /// 与真实事务回调共用的主actor内存状态，界面只读取/转交意图。
    let celebrationModel: TodayCompletionCelebrationViewModel
    private(set) var celebrationVerificationFailed = false

    private let context: ModelContext
    private let queryService: TodayTaskQueryService
    private let rewardLedger: RewardLedgerService
    private let dailyRewardQuery: DailyRewardQueryService
    private let dateProvider: any DateProviding
    private var calendar: Calendar
    private let timeZone: TimeZone
    // 窄读取闭包不跨并发域；本MainActor模型同步调用并保护其捕获的存储上下文。
    private let readCelebrationSnapshot: () throws -> TodayTasksSnapshot
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "Today")

    /// 注入时间环境和只读校验边界；初始化不访问数据库或预生成仪式。
    /// - Parameters:
    ///   - context: 组合根共享的主actor写上下文，本模型只读且不代保存其他草稿。
    ///   - calendar: 今日日期计算使用的日历。
    ///   - timeZone: 任务日期与排序的时区。
    ///   - dateProvider: 可替换的墙上时钟，单测使用固定时间。
    ///   - celebrationModel: 跨页面保留的状态；未注入时由本模型持有一个新实例。
    ///   - readCelebrationSnapshot: 仅替换附加资格读取，便于验证故障不影响任务/奖励；主actor同步调用。
    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding,
        celebrationModel: TodayCompletionCelebrationViewModel? = nil,
        readCelebrationSnapshot: (() throws -> TodayTasksSnapshot)? = nil
    ) {
        self.context = context
        rewardLedger = RewardLedgerService(context: context)
        dailyRewardQuery = DailyRewardQueryService(context: context, calendar: calendar, timeZone: timeZone)
        queryService = TodayTaskQueryService(
            context: context,
            calendar: calendar,
            timeZone: timeZone
        )
        self.dateProvider = dateProvider
        // Observable属性的修改会访问self；先在局部副本设置时区，避免依赖尚未初始化时访问self。
        var normalizedCalendar = calendar
        normalizedCalendar.timeZone = timeZone
        self.calendar = normalizedCalendar
        self.timeZone = timeZone
        self.celebrationModel = celebrationModel ?? TodayCompletionCelebrationViewModel()
        // 仪式需要完整审计，但普通任务仍能在账本故障时使用；不把两个读取边界合并。
        let celebrationQuery = TodayTaskQueryService(
            context: context, calendar: calendar, timeZone: timeZone, validatesCompletionAudit: true)
        self.readCelebrationSnapshot =
            readCelebrationSnapshot ?? {
                guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
                let now = dateProvider.now()
                let date = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
                return try celebrationQuery.snapshot(for: date, at: now)
            }
    }

    /// 前台刷新只读取注入时钟，不重新查询或修改任务与账本。
    func makeTimingPresentation(for task: KidTaskNavigationItem) -> KidTaskTimingPresentation {
        KidTaskTimingPresentation(task: task, at: dateProvider.now())
    }

    /// 重新读取今天的实例。失败时保留明确页面状态，并记录不含孩子隐私的错误类型。
    func load() {
        state = .loading
        do {
            let now = dateProvider.now()
            let date = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
            let snapshot = try queryService.snapshot(for: date, at: now)
            state = .loaded(makeContent(from: snapshot))
            refreshCelebration()
        } catch {
            logger.error("今日任务加载失败：\(String(describing: type(of: error)), privacy: .public)")
            state = .failed
            celebrationModel.invalidate()
        }
        // 两类查询独立失败；孩子不能因资产故障失去任务，也不能因任务损坏得到假余额。
        loadRewards()
    }

    /// 仅接新自行确认成功回调；辅助查询失败不能撤销已保存的打卡或奖励。
    func receive(completion: TaskCompletionResult) {
        guard completion.didComplete else { return }
        withCelebrationSnapshot(consumingOnFailure: completion.completionID) {
            celebrationModel.receive(completion: completion, snapshot: $0)
        }
    }

    /// 新家长通过后验证当天事实；历史已读收据和退回不从这个入口投递。
    func receive(review: TaskSubmissionReviewResult) {
        guard review.didReview, review.state == .approved, !review.rewardIsRevoked,
            let completionID = review.completionID
        else { return }
        withCelebrationSnapshot(consumingOnFailure: completionID) {
            celebrationModel.receive(review: review, snapshot: $0)
        }
    }

    /// 前台、返回及撤销只验证现有资格；恢复查询不重新生成已经撤下的仪式。
    /// - Note: 无事件且无失败时不额外读库；构造和普通历史加载也不会触发新庆祝。
    func refreshCelebration() {
        guard celebrationModel.event != nil || celebrationVerificationFailed else { return }
        withCelebrationSnapshot { celebrationModel.refresh(snapshot: $0) }
    }

    private func withCelebrationSnapshot(
        consumingOnFailure completionID: UUID? = nil, _ apply: (TodayTasksSnapshot) -> Void
    ) {
        do {
            apply(try readCelebrationSnapshot())
            celebrationVerificationFailed = false
        } catch {
            celebrationModel.invalidate(consuming: completionID)
            celebrationVerificationFailed = true
            // 错误只属于附加仪式，不回抛给保存事务；下一UI卡独立呈现此标志与重试入口。
            logger.error("今日仪式校验失败：\(String(describing: type(of: error)), privacy: .public)")
        }
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
        loadDailyRewards()
    }

    /// 今日所得可以单独重试；查询失败清掉旧值，但不隐藏真实钱包或今日任务。
    func loadDailyRewards() {
        dailyRewardState = .loading
        do {
            dailyRewardState = .loaded(try dailyRewardQuery.summary(at: dateProvider.now()))
        } catch {
            logger.error("今日所得加载失败：\(String(describing: type(of: error)), privacy: .public)")
            dailyRewardState = .failed
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
            isAllCompleted: snapshot.isAllCompleted,
            emptyReason: snapshot.emptyReason
        )
    }
}
