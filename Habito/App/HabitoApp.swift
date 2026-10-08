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
    private let dateProvider: any DateProviding
    private let notificationRebuildService: NotificationRebuildService
    private let notificationNavigationService: NotificationNavigationService
    private let taskSessionModelFactory: TaskSessionViewModelFactory
    private let taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory
    @State private var notificationRebuildTrigger: NotificationRebuildTrigger
    @State private var todayModel: TodayViewModel
    @State private var childRewardFeedbackModel: ChildRewardFeedbackViewModel
    @State private var parentGateModel: ParentGateViewModel
    @State private var parentTaskTemplatesModel: ParentTaskTemplateListViewModel
    @State private var parentTodayModel: ParentTodayTaskViewModel
    @State private var statisticsModel: GrowthStatisticsViewModel
    @State private var petProfileModel: PetProfileViewModel
    @State private var familyProfileModel: FamilyProfileEditorViewModel
    @State private var parentReviewModel: ParentReviewViewModel
    @State private var parentCalendarModel: ParentCalendarDayViewModel
    @State private var parentNotificationModel: ParentNotificationDiagnosticsViewModel

    init() {
        let container: ModelContainer
        let credentialStore: any ParentPINCredentialStoring
        let notificationProvider: any NotificationPermissionProviding
        let notificationScheduler: any NotificationRequestScheduling
        let dateProvider: any DateProviding
        do {
            #if DEBUG
                if let configuration = UITestLaunchConfiguration.current {
                    dateProvider = try configuration.makeDateProvider()
                    container = try configuration.makeContainer()
                    let uiTestCredentialStore = configuration.makeCredentialStore()
                    if configuration.shouldReset {
                        try uiTestCredentialStore.removeCredential()
                    }
                    credentialStore = uiTestCredentialStore
                    let uiTestNotificationService = UITestNotificationPermissionProvider(
                        deniesAuthorization: configuration.shouldDenyNotifications,
                        failsScheduling: configuration.shouldFailNotificationScheduling,
                        yieldsBeforeDiagnostics: configuration.shouldSeedTemplateOnly
                    )
                    notificationProvider = uiTestNotificationService
                    notificationScheduler = uiTestNotificationService
                    let calendar = Calendar(identifier: .gregorian)
                    let timeZone = TimeZone.autoupdatingCurrent
                    try UITestSeedService.prepare(
                        container: container,
                        shouldReset: configuration.shouldReset,
                        shouldSeedSampleData: configuration.shouldSeedSampleData,
                        shouldSeedTemplateOnly: configuration.shouldSeedTemplateOnly,
                        now: dateProvider.now(),
                        calendar: calendar,
                        timeZone: timeZone,
                        scenario: try UITestTaskScenario.parse(arguments: ProcessInfo.processInfo.arguments)
                    )
                    try UITestRewardReceiptProbe.prepare(
                        context: container.mainContext, arguments: ProcessInfo.processInfo.arguments)
                } else {
                    dateProvider = SystemDateProvider()
                    container = try AppModelContainer.make()
                    credentialStore = KeychainParentPINCredentialStore()
                    let notificationService = LocalNotificationService()
                    notificationProvider = notificationService
                    notificationScheduler = notificationService
                }
            #else
                dateProvider = SystemDateProvider()
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
        self.dateProvider = dateProvider
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone.autoupdatingCurrent
        let rebuildTrigger = NotificationRebuildTrigger()
        _familyProfileModel = State(initialValue: Self.makeFamilyProfileModel(context: container.mainContext))
        _petProfileModel = State(
            initialValue: Self.makePetProfileModel(
                context: container.mainContext, calendar: calendar, timeZone: timeZone, now: dateProvider.now))
        let overviewQuery = GrowthStatisticsQueryService(
            context: container.mainContext, calendar: calendar, timeZone: timeZone)
        let overviewModel = ParentTodayOverviewViewModel(service: overviewQuery, now: dateProvider.now)
        _statisticsModel = State(
            initialValue: GrowthStatisticsViewModel(
                service: Self.makeStatisticsService(
                    context: container.mainContext, calendar: calendar, timeZone: timeZone),
                now: dateProvider.now))
        let notificationOperationGate = NotificationOperationGate()
        // 全家账本与完成/撤销共用主写上下文；服务通过工厂注入页面，不由 View 发奖。
        let completionService = TaskCompletionService(context: container.mainContext)
        let undoService = TaskCompletionUndoService(context: container.mainContext)
        let submissionService = TaskSubmissionService(context: container.mainContext)
        #if DEBUG
            let reviewService = UITestReviewServiceFactory.make(
                context: container.mainContext, arguments: ProcessInfo.processInfo.arguments)
        #else
            let reviewService = TaskSubmissionReviewService(context: container.mainContext)
        #endif
        _notificationRebuildTrigger = State(initialValue: rebuildTrigger)
        notificationRebuildService = NotificationRebuildService(
            context: container.mainContext,
            scheduler: notificationScheduler,
            permissionProvider: notificationProvider,
            calendar: calendar,
            timeZone: timeZone,
            operationGate: notificationOperationGate
        )
        notificationNavigationService = NotificationNavigationService(context: container.mainContext)
        let notificationPermissionService = NotificationPermissionService(
            context: container.mainContext,
            provider: notificationProvider
        )
        // 今日模型持有跨导航的单一仪式状态；回调捕获这个实例，不由执行页另建去重集合。
        #if DEBUG
            let todayModel = UITestTodayViewModelFactory.make(
                context: container.mainContext, calendar: calendar, timeZone: timeZone,
                dateProvider: dateProvider, arguments: ProcessInfo.processInfo.arguments)
        #else
            let todayModel = TodayViewModel(
                context: container.mainContext, calendar: calendar, timeZone: timeZone, dateProvider: dateProvider)
        #endif
        _todayModel = State(initialValue: todayModel)
        _childRewardFeedbackModel = State(
            initialValue: ChildRewardFeedbackViewModel(
                service: Self.makeChildReceiptService(context: container.mainContext), dateProvider: dateProvider))
        taskSessionModelFactory = TaskSessionViewModelFactory(
            context: container.mainContext,
            calendar: calendar,
            timeZone: timeZone,
            dateProvider: dateProvider,
            snoozeService: TaskSnoozeService(
                context: container.mainContext,
                scheduler: notificationScheduler,
                permissionProvider: notificationProvider,
                calendar: calendar,
                timeZone: timeZone,
                operationGate: notificationOperationGate
            ),
            notificationRebuildTrigger: rebuildTrigger,
            completionService: completionService,
            undoService: undoService,
            submissionService: submissionService,
            onCompletionSaved: { todayModel.receive(completion: $0) },
            onCompletionChanged: todayModel.refreshCelebration
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
                notificationRebuildTrigger: rebuildTrigger,
                completionService: completionService,
                overviewModel: overviewModel
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
        _parentReviewModel = State(
            initialValue: ParentReviewViewModel(
                context: container.mainContext, dateProvider: dateProvider,
                notificationRebuildTrigger: rebuildTrigger, reviewService: reviewService,
                onApprovalSaved: { todayModel.receive(review: $0) })
        )
        _parentNotificationModel = State(
            initialValue: ParentNotificationDiagnosticsViewModel(
                service: notificationPermissionService,
                rebuildTrigger: rebuildTrigger
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                todayModel: todayModel,
                childRewardFeedbackModel: childRewardFeedbackModel,
                taskSessionModelFactory: taskSessionModelFactory,
                parentGateModel: parentGateModel,
                parentTaskTemplatesModel: parentTaskTemplatesModel,
                parentTodayModel: parentTodayModel,
                statisticsModel: statisticsModel,
                familyProfileModel: familyProfileModel,
                petProfileModel: petProfileModel,
                parentReviewModel: parentReviewModel,
                parentCalendarModel: parentCalendarModel,
                parentNotificationModel: parentNotificationModel,
                taskTemplateEditorModelFactory: taskTemplateEditorModelFactory,
                notificationRebuildService: notificationRebuildService,
                notificationRebuildTrigger: notificationRebuildTrigger,
                notificationResponseRouter: appDelegate.notificationResponseRouter,
                notificationNavigationService: notificationNavigationService,
                dateProvider: dateProvider
            )
            .onAppear(perform: connectLifecycleEvents)
        }
        .modelContainer(modelContainer)
    }

    private func connectLifecycleEvents() {
        appDelegate.connectNotificationRebuildTrigger(notificationRebuildTrigger)
    }

    /// 读取失败探针只在显式隔离Debug测试启用；Release没有失败工厂或合成库路径。
    private static func makePetProfileModel(
        context: ModelContext, calendar: Calendar, timeZone: TimeZone,
        now: @escaping () -> Date
    ) -> PetProfileViewModel {
        #if DEBUG
            UITestPetProfileFactory.make(
                context: context, arguments: ProcessInfo.processInfo.arguments,
                calendar: calendar, timeZone: timeZone, now: now)
        #else
            let service = PetCareService(context: context, calendar: calendar, timeZone: timeZone)
            return PetProfileViewModel(loadSnapshot: service.load, feedPet: service.feed, now: now)
        #endif
    }

    private static func makeFamilyProfileModel(context: ModelContext) -> FamilyProfileEditorViewModel {
        #if DEBUG
            UITestFamilyProfileEditorFactory.make(context: context, arguments: ProcessInfo.processInfo.arguments)
        #else
            let service = FamilyProfileService(context: context)
            return FamilyProfileEditorViewModel(loadNames: service.load, saveNames: service.save)
        #endif
    }

    /// 读取失败探针只在显式隔离Debug测试启用；Release没有失败工厂或合成库路径。
    private static func makeStatisticsService(context: ModelContext, calendar: Calendar, timeZone: TimeZone)
        -> GrowthStatisticsQueryService
    {
        #if DEBUG
            UITestStatisticsServiceFactory.make(
                context: context, calendar: calendar, timeZone: timeZone,
                arguments: ProcessInfo.processInfo.arguments)
        #else
            GrowthStatisticsQueryService(context: context, calendar: calendar, timeZone: timeZone)
        #endif
    }

    /// 只有测试组合根替换保存边界；普通运行始终使用真实服务。
    private static func makeChildReceiptService(context: ModelContext) -> ChildRewardReceiptService {
        #if DEBUG
            UITestChildReceiptServiceFactory.make(context: context, arguments: ProcessInfo.processInfo.arguments)
        #else
            ChildRewardReceiptService(context: context)
        #endif
    }
}
