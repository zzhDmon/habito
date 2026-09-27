import Foundation
import Observation
import OSLog
import SwiftData

/// 驱动家长今日实例列表，并把查询、时钟和写事务隔离在 View 之外。
@MainActor
@Observable
final class ParentTodayTaskViewModel {
    private(set) var state: ParentTodayTaskListState = .loading
    var isActionErrorPresented = false

    private let queryService: TodayTaskQueryService
    private let managementService: ParentTodayTaskManagementService
    private let dateProvider: any DateProviding
    private let notificationRebuildTrigger: NotificationRebuildTrigger
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "ParentToday")

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger()
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        queryService = TodayTaskQueryService(
            context: context,
            calendar: configuredCalendar,
            timeZone: timeZone
        )
        managementService = ParentTodayTaskManagementService(
            context: context,
            calendar: configuredCalendar,
            timeZone: timeZone
        )
        self.dateProvider = dateProvider
        self.notificationRebuildTrigger = notificationRebuildTrigger
        self.calendar = configuredCalendar
        self.timeZone = timeZone
    }

    func load() {
        state = .loading
        do {
            let now = dateProvider.now()
            let date = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
            let snapshot = try queryService.snapshot(for: date, at: now)
            state = .loaded(ParentTodayTaskListContent(date: date, items: snapshot.tasks))
        } catch {
            logger.error("家长今日实例加载失败：\(String(describing: type(of: error)), privacy: .public)")
            state = .failed
        }
    }

    func reschedule(occurrenceID: UUID, to scheduledAt: Date) {
        perform {
            try managementService.reschedule(
                occurrenceID: occurrenceID,
                to: scheduledAt,
                at: dateProvider.now()
            )
        }
    }

    func skip(occurrenceID: UUID) {
        perform {
            try managementService.skip(occurrenceID: occurrenceID, at: dateProvider.now())
        }
    }

    func restore(occurrenceID: UUID) {
        perform {
            try managementService.restore(occurrenceID: occurrenceID, at: dateProvider.now())
        }
    }

    func correctAsCompleted(occurrenceID: UUID) {
        perform {
            try managementService.correctAsCompleted(
                occurrenceID: occurrenceID,
                at: dateProvider.now()
            )
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            notificationRebuildTrigger.requestRebuild()
            load()
        } catch {
            logger.error("家长今日实例操作失败：\(String(describing: type(of: error)), privacy: .public)")
            isActionErrorPresented = true
        }
    }
}
