import Foundation
import Observation
import OSLog
import SwiftData

/// 驱动孩子今日页的可观察状态，并隔离查询与展示格式化逻辑。
@MainActor
@Observable
final class TodayViewModel {
    private(set) var state: TodayViewState = .loading

    private let queryService: TodayTaskQueryService
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
    }

    private func makeContent(from snapshot: TodayTasksSnapshot) -> TodayScreenContent {
        let tasks = snapshot.visibleTasks.map(makeNavigationItem)
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

    private func makeNavigationItem(from item: TodayTaskItem) -> KidTaskNavigationItem {
        let components = calendar.dateComponents([.hour, .minute], from: item.scheduledAt)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let targetMinutes = max(1, Int(ceil(item.targetDurationSeconds / 60)))

        return KidTaskNavigationItem(
            id: item.id,
            title: item.title,
            iconName: item.iconName,
            scheduledTimeText: String(format: "%02d:%02d", hour, minute),
            targetDurationText: String.localizedStringWithFormat(
                String(localized: "kidTask.durationMinutesFormat"),
                targetMinutes
            ),
            status: item.status,
            statusText: statusText(for: item.status),
            statusIconName: statusIconName(for: item.status)
        )
    }

    private func statusText(for status: TaskOccurrenceStatus) -> String {
        switch status {
        case .pending:
            String(localized: "kidTask.statusPending")
        case .inProgress:
            String(localized: "kidTask.statusInProgress")
        case .completed:
            String(localized: "kidTask.statusCompleted")
        case .skipped:
            String(localized: "kidTask.statusSkipped")
        }
    }

    private func statusIconName(for status: TaskOccurrenceStatus) -> String {
        switch status {
        case .pending:
            HabitoDesign.Symbol.pending
        case .inProgress:
            "play.circle.fill"
        case .completed:
            HabitoDesign.Symbol.completed
        case .skipped:
            "forward.end.circle.fill"
        }
    }
}
