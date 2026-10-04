import OSLog
import SwiftUI

/// 孩子模式的根导航视图。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [KidRoute] = []
    @State private var todayModel: TodayViewModel
    @State private var parentGateModel: ParentGateViewModel
    @State private var parentTaskTemplatesModel: ParentTaskTemplateListViewModel
    @State private var parentTodayModel: ParentTodayTaskViewModel
    @State private var parentCalendarModel: ParentCalendarDayViewModel
    @State private var parentNotificationModel: ParentNotificationDiagnosticsViewModel
    @State private var notificationRebuildTrigger: NotificationRebuildTrigger
    @State private var notificationResponseRouter: NotificationResponseRouter
    @State private var isParentGatePresented = false
    private let taskSessionModelFactory: TaskSessionViewModelFactory
    private let taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory
    private let notificationRebuildService: NotificationRebuildService
    private let notificationNavigationService: NotificationNavigationService
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "NotificationRebuild")

    init(
        todayModel: TodayViewModel,
        taskSessionModelFactory: TaskSessionViewModelFactory,
        parentGateModel: ParentGateViewModel,
        parentTaskTemplatesModel: ParentTaskTemplateListViewModel,
        parentTodayModel: ParentTodayTaskViewModel,
        parentCalendarModel: ParentCalendarDayViewModel,
        parentNotificationModel: ParentNotificationDiagnosticsViewModel,
        taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory,
        notificationRebuildService: NotificationRebuildService,
        notificationRebuildTrigger: NotificationRebuildTrigger,
        notificationResponseRouter: NotificationResponseRouter,
        notificationNavigationService: NotificationNavigationService
    ) {
        _todayModel = State(initialValue: todayModel)
        self.taskSessionModelFactory = taskSessionModelFactory
        _parentGateModel = State(initialValue: parentGateModel)
        _parentTaskTemplatesModel = State(initialValue: parentTaskTemplatesModel)
        _parentTodayModel = State(initialValue: parentTodayModel)
        _parentCalendarModel = State(initialValue: parentCalendarModel)
        _parentNotificationModel = State(initialValue: parentNotificationModel)
        _notificationRebuildTrigger = State(initialValue: notificationRebuildTrigger)
        _notificationResponseRouter = State(initialValue: notificationResponseRouter)
        self.taskTemplateEditorModelFactory = taskTemplateEditorModelFactory
        self.notificationRebuildService = notificationRebuildService
        self.notificationNavigationService = notificationNavigationService
    }

    var body: some View {
        NavigationStack(path: $path) {
            KidTodayView(
                state: todayModel.state,
                onSelectTask: showTask,
                onRetry: loadToday
            )
            .toolbar {
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
                case let .task(occurrenceID):
                    KidTaskSessionView(
                        model: taskSessionModelFactory.makeModel(for: occurrenceID),
                        onExit: loadToday
                    )
                }
            }
        }
        .task(loadToday)
        .task(id: notificationRebuildTrigger.revision) {
            await rebuildNotifications()
        }
        .task(id: notificationResponseRouter.revision) {
            routePendingNotificationResponse()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            notificationRebuildTrigger.requestRebuild()
        }
        .sheet(isPresented: $isParentGatePresented, onDismiss: loadToday) {
            ParentGateView(
                model: parentGateModel,
                taskTemplatesModel: parentTaskTemplatesModel,
                parentTodayModel: parentTodayModel,
                parentCalendarModel: parentCalendarModel,
                parentNotificationModel: parentNotificationModel,
                taskTemplateEditorModelFactory: taskTemplateEditorModelFactory
            )
        }
    }

    private func showTask(_ task: KidTaskNavigationItem) {
        path.append(.task(task.id))
    }

    private func loadToday() {
        todayModel.load()
    }

    private func openParentGate() {
        parentGateModel.prepareForPresentation()
        isParentGatePresented = true
    }

    private func rebuildNotifications() async {
        notificationRebuildTrigger.recordStarted()
        do {
            let result = try await notificationRebuildService.rebuild(at: .now)
            try Task.checkCancellation()
            notificationRebuildTrigger.record(result, checkedAt: .now)
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
        guard let identifier = notificationResponseRouter.consumePendingRequestIdentifier() else {
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
}
