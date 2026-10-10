import OSLog
import SwiftUI

/// 孩子模式的根导航视图。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [KidRoute] = []
    @State private var todayModel: TodayViewModel
    @State private var childRewardFeedbackModel: ChildRewardFeedbackViewModel
    @State private var parentGateModel: ParentGateViewModel
    @State private var parentTaskTemplatesModel: ParentTaskTemplateListViewModel
    @State private var parentTodayModel: ParentTodayTaskViewModel
    @State private var statisticsModel: GrowthStatisticsViewModel
    @State private var petProfileModel: PetProfileViewModel
    @State private var petGrowthFeedbackModel: PetGrowthFeedbackViewModel
    @State private var familyProfileModel: FamilyProfileEditorViewModel
    @State private var parentReviewModel: ParentReviewViewModel
    @State private var parentCalendarModel: ParentCalendarDayViewModel
    @State private var parentNotificationModel: ParentNotificationDiagnosticsViewModel
    @State private var notificationRebuildTrigger: NotificationRebuildTrigger
    @State private var notificationResponseRouter: NotificationResponseRouter
    @State private var isParentGatePresented = false
    @State private var isParentEditorProtected = false
    private let taskSessionModelFactory: TaskSessionViewModelFactory
    private let taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory
    private let notificationRebuildService: NotificationRebuildService
    private let notificationNavigationService: NotificationNavigationService
    private let dateProvider: any DateProviding
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "NotificationRebuild")

    init(
        todayModel: TodayViewModel,
        childRewardFeedbackModel: ChildRewardFeedbackViewModel,
        taskSessionModelFactory: TaskSessionViewModelFactory,
        parentGateModel: ParentGateViewModel,
        parentTaskTemplatesModel: ParentTaskTemplateListViewModel,
        parentTodayModel: ParentTodayTaskViewModel,
        statisticsModel: GrowthStatisticsViewModel,
        familyProfileModel: FamilyProfileEditorViewModel,
        petProfileModel: PetProfileViewModel,
        petGrowthFeedbackModel: PetGrowthFeedbackViewModel,
        parentReviewModel: ParentReviewViewModel,
        parentCalendarModel: ParentCalendarDayViewModel,
        parentNotificationModel: ParentNotificationDiagnosticsViewModel,
        taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory,
        notificationRebuildService: NotificationRebuildService,
        notificationRebuildTrigger: NotificationRebuildTrigger,
        notificationResponseRouter: NotificationResponseRouter,
        notificationNavigationService: NotificationNavigationService,
        dateProvider: any DateProviding
    ) {
        _todayModel = State(initialValue: todayModel)
        _childRewardFeedbackModel = State(initialValue: childRewardFeedbackModel)
        self.taskSessionModelFactory = taskSessionModelFactory
        _parentGateModel = State(initialValue: parentGateModel)
        _parentTaskTemplatesModel = State(initialValue: parentTaskTemplatesModel)
        _parentTodayModel = State(initialValue: parentTodayModel)
        _statisticsModel = State(initialValue: statisticsModel)
        _familyProfileModel = State(initialValue: familyProfileModel)
        _petProfileModel = State(initialValue: petProfileModel)
        _petGrowthFeedbackModel = State(initialValue: petGrowthFeedbackModel)
        _parentReviewModel = State(initialValue: parentReviewModel)
        _parentCalendarModel = State(initialValue: parentCalendarModel)
        _parentNotificationModel = State(initialValue: parentNotificationModel)
        _notificationRebuildTrigger = State(initialValue: notificationRebuildTrigger)
        _notificationResponseRouter = State(initialValue: notificationResponseRouter)
        self.taskTemplateEditorModelFactory = taskTemplateEditorModelFactory
        self.notificationRebuildService = notificationRebuildService
        self.notificationNavigationService = notificationNavigationService
        self.dateProvider = dateProvider
    }

    var body: some View {
        NavigationStack(path: $path) {
            KidTodayView(
                state: todayModel.state,
                rewardState: todayModel.rewardState,
                makeTimingPresentation: todayModel.makeTimingPresentation,
                onSelectTask: showTask,
                onRetry: loadToday,
                onRetryRewards: todayModel.loadRewards,
                onOpenPet: showPet,
                onOpenParent: openParentGate,
                dailyRewardState: todayModel.dailyRewardState,
                onRetryDailyRewards: todayModel.loadDailyRewards,
                feedbackState: childRewardFeedbackModel.state,
                acknowledgementFailed: childRewardFeedbackModel.acknowledgementFailed,
                onContinueReceipt: childRewardFeedbackModel.acknowledge,
                onRetryReceipt: childRewardFeedbackModel.load,
                celebrationEvent: todayModel.celebrationModel.event,
                celebrationVerificationFailed: todayModel.celebrationVerificationFailed,
                onClaimCelebration: todayModel.celebrationModel.claimAnimation,
                onContinueCelebration: todayModel.celebrationModel.dismiss,
                onRetryCelebration: todayModel.refreshCelebration,
                petGrowthEvent: petGrowthFeedbackModel.event, petGrowthFailed: petGrowthFeedbackModel.failed,
                onDismissPetGrowth: petGrowthFeedbackModel.dismiss, onRetryPetGrowth: petGrowthFeedbackModel.refresh
            )
            .toolbar {
                #if DEBUG
                    if notificationResponseRouter.preparedUITestRequestIdentifier != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(
                                "testing.openNotification", systemImage: "bell",
                                action: notificationResponseRouter.deliverPreparedUITestResponse
                            )
                            .frame(
                                minWidth: HabitoDesign.Layout.minimumTapSize,
                                minHeight: HabitoDesign.Layout.minimumTapSize
                            )
                            .accessibilityIdentifier(HabitoAccessibilityID.testingNotificationResponse)
                        }
                    }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        "parentGate.entry",
                        systemImage: "person.badge.key.fill",
                        action: openParentGate
                    )
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentEntry)
                    .accessibilityHint("parentGate.entryHint")
                }
            }
            .navigationDestination(for: KidRoute.self) { route in
                switch route {
                case .pet:
                    PetHomeView(
                        model: petProfileModel, onOpenParent: openParentGate,
                        levelUp: petGrowthFeedbackModel.event, growthCheckFailed: petGrowthFeedbackModel.failed,
                        onDismissLevelUp: petGrowthFeedbackModel.dismiss, onRetryGrowth: petGrowthFeedbackModel.refresh)
                case let .task(occurrenceID):
                    KidTaskSessionView(
                        model: taskSessionModelFactory.makeModel(for: occurrenceID),
                        cameraModel: taskSessionModelFactory.makeCameraModel(),
                        onExit: loadToday
                    )
                }
            }
        }
        .tint(HabitoDesign.Manga.successInk)
        .task(loadToday)
        .task(id: notificationRebuildTrigger.revision) {
            await rebuildNotifications()
        }
        .task(id: notificationResponseRouter.revision) {
            routePendingNotificationResponse()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadToday()
            notificationRebuildTrigger.requestRebuild()
        }
        .onChange(of: path) { _, routes in
            if routes.isEmpty { loadToday() }
        }
        .fullScreenCover(isPresented: $isParentGatePresented, onDismiss: loadToday) {
            ParentGateView(
                model: parentGateModel,
                taskTemplatesModel: parentTaskTemplatesModel,
                parentTodayModel: parentTodayModel,
                statisticsModel: statisticsModel,
                familyProfileModel: familyProfileModel,
                parentReviewModel: parentReviewModel,
                parentCalendarModel: parentCalendarModel,
                parentNotificationModel: parentNotificationModel,
                taskTemplateEditorModelFactory: taskTemplateEditorModelFactory,
                onEditorExitProtectionChanged: updateEditorExitProtection
            )
        }
    }

    private func showPet() {
        path.append(.pet)
    }

    private func showTask(_ task: KidTaskNavigationItem) {
        path.append(.task(task.id))
    }

    private func loadToday() {
        todayModel.load()
        // 家长可能有未保存草稿，执行页也有自己的完成反馈；仅首页可见时读审核收据。
        if !isParentGatePresented, path.isEmpty { childRewardFeedbackModel.load() }
        // 宠物页只读；PIN表单关闭后再刷新，绝不读取家长未保存草稿。
        if !isParentGatePresented, path.last == .pet { petProfileModel.load() }
        if !isParentGatePresented, path.isEmpty || path.last == .pet { petGrowthFeedbackModel.refresh() }
    }

    private func openParentGate() {
        parentGateModel.prepareForPresentation()
        isParentGatePresented = true
    }

    private func rebuildNotifications() async {
        notificationRebuildTrigger.recordStarted()
        do {
            let result = try await notificationRebuildService.rebuild(at: dateProvider.now())
            try Task.checkCancellation()
            // 重建会独立物化今日实例；TodayViewModel 持有只读值，不会随 SwiftData 写入自动刷新。
            // 排程部分失败也应显示已落盘的任务，确保无通知权限时仍可手动完成。
            loadToday()
            notificationRebuildTrigger.record(result, checkedAt: dateProvider.now())
            if !result.reconciliation.isSuccessful {
                logger.error("通知核对有 \(result.reconciliation.failures.count, privacy: .public) 项失败")
            }
        } catch is CancellationError {
            return
        } catch {
            notificationRebuildTrigger.recordFailure()
            logger.error("通知重建失败：\(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func routePendingNotificationResponse() {
        // 不消费仍受保护的通知：显式保存或放弃后再导航，避免通知强制撤下编辑器丢失输入。
        guard
            let identifier = notificationResponseRouter.consumePendingRequestIdentifier(
                isNavigationProtected: isParentEditorProtected
            )
        else {
            return
        }
        switch notificationNavigationService.destination(for: identifier) {
        case let .task(occurrenceID):
            isParentGatePresented = false
            path = [.task(occurrenceID)]
        case .home:
            isParentGatePresented = false
            path = []
            loadToday()
        case .ignored:
            break
        }
    }

    private func updateEditorExitProtection(_ protected: Bool) {
        isParentEditorProtected = protected
        if !protected { routePendingNotificationResponse() }
    }
}
