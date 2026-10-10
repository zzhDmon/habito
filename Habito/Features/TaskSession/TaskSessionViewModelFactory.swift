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
    private let submissionService: TaskSubmissionService
    private let onCompletionSaved: (@MainActor (TaskCompletionResult) -> Void)?
    private let onCompletionChanged: (@MainActor () -> Void)?

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding,
        snoozeService: TaskSnoozeService? = nil,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger(),
        completionService: TaskCompletionService? = nil,
        undoService: TaskCompletionUndoService? = nil,
        submissionService: TaskSubmissionService? = nil,
        onCompletionSaved: (@MainActor (TaskCompletionResult) -> Void)? = nil,
        onCompletionChanged: (@MainActor () -> Void)? = nil
    ) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.dateProvider = dateProvider
        self.snoozeService = snoozeService
        self.notificationRebuildTrigger = notificationRebuildTrigger
        self.completionService = completionService ?? TaskCompletionService(context: context)
        self.undoService = undoService ?? TaskCompletionUndoService(context: context)
        self.submissionService = submissionService ?? TaskSubmissionService(context: context)
        self.onCompletionSaved = onCompletionSaved
        self.onCompletionChanged = onCompletionChanged
    }

    /// 每个导航页面拥有独立采集会话；由组合根注入，View 不创建或配置系统摄像头。
    func makeCameraModel() -> TaskCameraViewModel {
        let service = FrontCameraService()
        return TaskCameraViewModel(service: service, previewSource: service.previewSource)
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
            undoService: undoService,
            submissionService: submissionService,
            onCompletionSaved: onCompletionSaved,
            onCompletionChanged: onCompletionChanged
        )
    }
}
