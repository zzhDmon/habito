import SwiftUI

/// 孩子模式的根导航视图。
struct RootView: View {
    let tasks: [KidTaskNavigationItem]

    @State private var path: [KidRoute] = []

    init(tasks: [KidTaskNavigationItem] = []) {
        self.tasks = tasks
    }

    var body: some View {
        NavigationStack(path: $path) {
            KidTodayView(tasks: tasks, onSelectTask: showTask)
                .navigationDestination(for: KidRoute.self) { route in
                    switch route {
                    case let .task(task):
                        KidTaskSessionView(task: task)
                    }
                }
        }
    }

    private func showTask(_ task: KidTaskNavigationItem) {
        path.append(.task(task))
    }
}

#Preview("孩子模式 · iPad 横屏") {
    RootView(tasks: [.previewReading])
        .frame(width: 1_194, height: 834)
}
