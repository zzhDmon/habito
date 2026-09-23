import SwiftUI

/// 孩子模式的根导航视图。
struct RootView: View {
    @State private var path: [KidRoute] = []
    @State private var todayModel: TodayViewModel
    private let taskSessionModelFactory: TaskSessionViewModelFactory

    init(
        todayModel: TodayViewModel,
        taskSessionModelFactory: TaskSessionViewModelFactory
    ) {
        _todayModel = State(initialValue: todayModel)
        self.taskSessionModelFactory = taskSessionModelFactory
    }

    var body: some View {
        NavigationStack(path: $path) {
            KidTodayView(
                state: todayModel.state,
                onSelectTask: showTask,
                onRetry: loadToday
            )
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
    }

    private func showTask(_ task: KidTaskNavigationItem) {
        path.append(.task(task))
    }

    private func loadToday() {
        todayModel.load()
    }
}
