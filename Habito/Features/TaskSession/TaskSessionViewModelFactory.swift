import Foundation
import SwiftData

/// 在应用组合根保存任务执行页所需依赖，并为每个稳定实例 ID 创建独立页面模型。
@MainActor
struct TaskSessionViewModelFactory {
    private let context: ModelContext
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let dateProvider: any DateProviding
    private let snoozeService: TaskSnoozeService?
    private let notificationRebuildTrigger: NotificationRebuildTrigger
    private let completionService: TaskCompletionService
    private let undoService: TaskCompletionUndoService

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding,
        snoozeService: TaskSnoozeService? = nil,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger(),
        completionService: TaskCompletionService? = nil,
        undoService: TaskCompletionUndoService? = nil
    ) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.dateProvider = dateProvider
        self.snoozeService = snoozeService
        self.notificationRebuildTrigger = notificationRebuildTrigger
        self.completionService = completionService ?? TaskCompletionService(context: context)
        self.undoService = undoService ?? TaskCompletionUndoService(context: context)
    }

    func makeModel(for occurrenceID: UUID) -> TaskSessionViewModel {
        TaskSessionViewModel(
            occurrenceID: occurrenceID,
            context: context,
            calendar: calendar,
            timeZone: timeZone,
            dateProvider: dateProvider,
            snoozeService: snoozeService,
            notificationRebuildTrigger: notificationRebuildTrigger,
            completionService: completionService,
            undoService: undoService
        )
    }
}
