import Foundation
import Observation
import OSLog
import SwiftData

/// 驱动家长日历单日查询、影响预览和确认写入。
@MainActor
@Observable
final class ParentCalendarDayViewModel {
    private(set) var snapshot: ParentCalendarDaySnapshot?
    private(set) var isLoading = true
    private(set) var isLoadFailed = false
    var selectedDate: Date
    var pendingImpact: ParentCalendarDayImpact?
    var isConfirmationPresented = false {
        didSet {
            if !isConfirmationPresented { pendingImpact = nil }
        }
    }
    var isActionErrorPresented = false

    private let service: ParentCalendarDayService
    private let dateProvider: any DateProviding
    private let notificationRebuildTrigger: NotificationRebuildTrigger
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "ParentCalendar")

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger()
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
        self.dateProvider = dateProvider
        self.notificationRebuildTrigger = notificationRebuildTrigger
        selectedDate = dateProvider.now()
        service = ParentCalendarDayService(
            context: context,
            calendar: configuredCalendar,
            timeZone: timeZone
        )
    }

    func load() {
        isLoading = true
        isLoadFailed = false
        do {
            let today = try localDate(dateProvider.now())
            snapshot = try service.snapshot(for: localDate(selectedDate), today: today)
        } catch {
            snapshot = nil
            isLoadFailed = true
            logger.error("家长日历加载失败：\(String(describing: type(of: error)), privacy: .public)")
        }
        isLoading = false
    }

    func preview(_ action: ParentCalendarDayAction) {
        do {
            pendingImpact = try service.preview(
                action,
                on: localDate(selectedDate),
                today: localDate(dateProvider.now())
            )
            isConfirmationPresented = true
        } catch {
            present(error)
        }
    }

    func confirmPendingAction() {
        guard let impact = pendingImpact else { return }
        isConfirmationPresented = false
        do {
            let now = dateProvider.now()
            _ = try service.apply(
                impact.action,
                on: impact.date,
                today: localDate(now),
                now: now
            )
            notificationRebuildTrigger.requestRebuild()
            load()
        } catch {
            present(error)
        }
    }

    func cancelPendingAction() {
        isConfirmationPresented = false
    }

    private func localDate(_ date: Date) throws -> LocalDate {
        try LocalDate(date: date, calendar: calendar, timeZone: timeZone)
    }

    private func present(_ error: Error) {
        logger.error("家长日历操作失败：\(String(describing: type(of: error)), privacy: .public)")
        isActionErrorPresented = true
    }
}
