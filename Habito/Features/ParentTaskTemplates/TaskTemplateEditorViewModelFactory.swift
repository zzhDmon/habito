import Foundation
import SwiftData

/// 在组合根持有编辑器依赖，并按类型安全路由创建页面模型。
@MainActor
struct TaskTemplateEditorViewModelFactory {
    private let context: ModelContext
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let dateProvider: any DateProviding
    private let notificationPermissionService: NotificationPermissionService
    private let notificationRebuildTrigger: NotificationRebuildTrigger

    init(
        context: ModelContext,
        calendar: Calendar,
        timeZone: TimeZone,
        dateProvider: any DateProviding,
        notificationPermissionService: NotificationPermissionService,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger()
    ) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.dateProvider = dateProvider
        self.notificationPermissionService = notificationPermissionService
        self.notificationRebuildTrigger = notificationRebuildTrigger
    }

    func makeModel(for route: ParentTaskTemplateRoute) -> TaskTemplateEditorViewModel {
        let templateID: UUID?
        switch route {
        case .create: templateID = nil
        case let .detail(id): templateID = id
        }
        return TaskTemplateEditorViewModel(
            templateID: templateID,
            service: TaskTemplateEditingService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            ),
            lifecycleService: TaskTemplateLifecycleService(
                context: context,
                calendar: calendar,
                timeZone: timeZone
            ),
            notificationPermissionService: notificationPermissionService,
            notificationRebuildTrigger: notificationRebuildTrigger,
            dateProvider: dateProvider,
            calendar: calendar,
            timeZone: timeZone
        )
    }
}
