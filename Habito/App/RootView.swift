import SwiftUI

/// 孩子模式的根导航视图。
struct RootView: View {
    @State private var path: [KidRoute] = []
    @State private var todayModel: TodayViewModel
    @State private var parentGateModel: ParentGateViewModel
    @State private var parentTaskTemplatesModel: ParentTaskTemplateListViewModel
    @State private var isParentGatePresented = false
    private let taskSessionModelFactory: TaskSessionViewModelFactory
    private let taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory

    init(
        todayModel: TodayViewModel,
        taskSessionModelFactory: TaskSessionViewModelFactory,
        parentGateModel: ParentGateViewModel,
        parentTaskTemplatesModel: ParentTaskTemplateListViewModel,
        taskTemplateEditorModelFactory: TaskTemplateEditorViewModelFactory
    ) {
        _todayModel = State(initialValue: todayModel)
        self.taskSessionModelFactory = taskSessionModelFactory
        _parentGateModel = State(initialValue: parentGateModel)
        _parentTaskTemplatesModel = State(initialValue: parentTaskTemplatesModel)
        self.taskTemplateEditorModelFactory = taskTemplateEditorModelFactory
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
                    Label("parentGate.entry", systemImage: "person.badge.key.fill")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier(HabitoAccessibilityID.parentEntry)
                        .accessibilityHint("parentGate.entryHint")
                        .accessibilityAction(named: "parentGate.openAction") {
                            openParentGate()
                        }
                        // 普通 Button 会优先识别点击并吞掉长按；入口只接受长按，避免孩子误触进入。
                        .onLongPressGesture(minimumDuration: 1, perform: openParentGate)
                }
            }
            .navigationDestination(for: KidRoute.self) { route in
                switch route {
                case let .task(task):
                    KidTaskSessionView(
                        model: taskSessionModelFactory.makeModel(for: task.id),
                        onExit: loadToday
                    )
                }
            }
        }
        .task(loadToday)
        .sheet(isPresented: $isParentGatePresented) {
            ParentGateView(
                model: parentGateModel,
                taskTemplatesModel: parentTaskTemplatesModel,
                taskTemplateEditorModelFactory: taskTemplateEditorModelFactory
            )
        }
    }

    private func showTask(_ task: KidTaskNavigationItem) {
        path.append(.task(task))
    }

    private func loadToday() {
        todayModel.load()
    }

    private func openParentGate() {
        parentGateModel.prepareForPresentation()
        isParentGatePresented = true
    }
}
