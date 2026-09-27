import SwiftData
import SwiftUI

/// Habito 的应用入口，同时也是依赖组合根。
///
/// V0 先在这里创建全局唯一的 SwiftData 容器。后续新增通知、时钟等系统服务时，
/// 也应在组合根完成装配，再通过环境或初始化参数传给功能模块，避免页面自行创建依赖。
@main
struct HabitoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let notificationRebuildService: NotificationRebuildService
    private let notificationNavigationService: NotificationNavigationService
    private let taskSessionModelFactory: TaskSessionViewModelFactory
    private let taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory
    @State private var notificationRebuildTrigger: NotificationRebuildTrigger
    @State private var todayModel: TodayViewModel
    @State private var parentGateModel: ParentGateViewModel
    @State private var parentTaskTemplatesModel: ParentTaskTemplateListViewModel
    @State private var parentTodayModel: ParentTodayTaskViewModel
    @State private var parentCalendarModel: ParentCalendarDayViewModel
    @State private var parentNotificationModel: ParentNotificationDiagnosticsViewModel

    init() {
        let container: ModelContainer
        let credentialStore: any ParentPINCredentialStoring
        let notificationProvider: any NotificationPermissionProviding
        let notificationScheduler: any NotificationRequestScheduling
        do {
            #if DEBUG
                if let configuration = UITestLaunchConfiguration.current {
                    container = try configuration.makeContainer()
                    let uiTestCredentialStore = configuration.makeCredentialStore()
                    if configuration.shouldReset {
                        try uiTestCredentialStore.removeCredential()
                    }
                    credentialStore = uiTestCredentialStore
                    let uiTestNotificationService = UITestNotificationPermissionProvider()
                    notificationProvider = uiTestNotificationService
                    notificationScheduler = uiTestNotificationService
                    let calendar = Calendar(identifier: .gregorian)
                    let timeZone = TimeZone.autoupdatingCurrent
                    try UITestSeedService.prepare(
                        container: container,
                        shouldReset: configuration.shouldReset,
                        shouldSeedSampleData: configuration.shouldSeedSampleData,
                        now: .now,
                        calendar: calendar,
                        timeZone: timeZone
                    )
                } else {
                    container = try AppModelContainer.make()
                    credentialStore = KeychainParentPINCredentialStore()
                    let notificationService = LocalNotificationService()
                    notificationProvider = notificationService
                    notificationScheduler = notificationService
                }
            #else
                container = try AppModelContainer.make()
                credentialStore = KeychainParentPINCredentialStore()
                let notificationService = LocalNotificationService()
                notificationProvider = notificationService
                notificationScheduler = notificationService
            #endif
        } catch {
            // 持久化容器不可用时，继续运行会让后续读写行为不可预测，
            // 因此启动阶段直接失败并保留明确原因。
            fatalError("无法创建 Habito 数据容器：\(error.localizedDescription)")
        }
        modelContainer = container
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone.autoupdatingCurrent
        let dateProvider = SystemDateProvider()
        let rebuildTrigger = NotificationRebuildTrigger()
        _notificationRebuildTrigger = State(initialValue: rebuildTrigger)
        notificationRebuildService = NotificationRebuildService(
            context: container.mainContext,
            scheduler: notificationScheduler,
            calendar: calendar,
            timeZone: timeZone
        )
        notificationNavigationService = NotificationNavigationService(context: container.mainContext)
        let notificationPermissionService = NotificationPermissionService(
            context: container.mainContext,
            provider: notificationProvider
        )
        _todayModel = State(
            initialValue: TodayViewModel(
                context: container.mainContext,
                calendar: calendar,
                timeZone: timeZone,
                dateProvider: dateProvider
            )
        )
        taskSessionModelFactory = TaskSessionViewModelFactory(
            context: container.mainContext,
            calendar: calendar,
            timeZone: timeZone,
            dateProvider: dateProvider,
            notificationRebuildTrigger: rebuildTrigger
        )
        taskTemplateEditorModelFactory = TaskTemplateEditorViewModelFactory(
            context: container.mainContext,
            calendar: calendar,
            timeZone: timeZone,
            dateProvider: dateProvider,
            notificationPermissionService: notificationPermissionService,
            notificationRebuildTrigger: rebuildTrigger
        )
        _parentGateModel = State(
            initialValue: ParentGateViewModel(
                context: container.mainContext,
                credentialStore: credentialStore
            )
        )
        _parentTaskTemplatesModel = State(
            initialValue: ParentTaskTemplateListViewModel(
                context: container.mainContext,
                calendar: calendar,
                timeZone: timeZone,
                dateProvider: dateProvider
            )
        )
        _parentTodayModel = State(
            initialValue: ParentTodayTaskViewModel(
                context: container.mainContext,
                calendar: calendar,
                timeZone: timeZone,
                dateProvider: dateProvider,
                notificationRebuildTrigger: rebuildTrigger
            )
        )
        _parentCalendarModel = State(
            initialValue: ParentCalendarDayViewModel(
                context: container.mainContext,
                calendar: calendar,
                timeZone: timeZone,
                dateProvider: dateProvider,
                notificationRebuildTrigger: rebuildTrigger
            )
        )
        _parentNotificationModel = State(
            initialValue: ParentNotificationDiagnosticsViewModel(
                service: notificationPermissionService
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                todayModel: todayModel,
                taskSessionModelFactory: taskSessionModelFactory,
                parentGateModel: parentGateModel,
                parentTaskTemplatesModel: parentTaskTemplatesModel,
                parentTodayModel: parentTodayModel,
                parentCalendarModel: parentCalendarModel,
                parentNotificationModel: parentNotificationModel,
                taskTemplateEditorModelFactory: taskTemplateEditorModelFactory,
                notificationRebuildService: notificationRebuildService,
                notificationRebuildTrigger: notificationRebuildTrigger,
                notificationResponseRouter: appDelegate.notificationResponseRouter,
                notificationNavigationService: notificationNavigationService
            )
        }
        .modelContainer(modelContainer)
    }
}
