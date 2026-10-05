import SwiftUI

/// 任务执行页容器，负责持有页面模型并响应 App 场景恢复。
struct KidTaskSessionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TaskSessionViewModel
    private let onExit: () -> Void

    init(model: TaskSessionViewModel, onExit: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onExit = onExit
    }

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.state {
            case .loading:
                ProgressView("taskSession.loading")
                    .controlSize(.large)
            case let .loaded(content):
                TaskSessionLoadedView(
                    content: content,
                    snoozeState: model.snoozeState,
                    onStartOrResume: model.startOrResume,
                    onPause: model.pause,
                    onSnooze: model.snooze,
                    onComplete: model.completeTask,
                    onUndoCompletion: model.undoCompletion,
                    currentDate: model.currentDate
                )
            case .failed:
                ContentUnavailableView {
                    Label("taskSession.errorTitle", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text("taskSession.errorDescription")
                } actions: {
                    Button("taskSession.retry", action: model.load)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .navigationTitle("kidTask.navigationTitle")
        .navigationBarTitleDisplayMode(.inline)
        .background(.background)
        .alert("taskSession.actionErrorTitle", isPresented: $model.isActionErrorPresented) {
        } message: {
            Text(LocalizedStringKey(model.actionFailure?.messageKey ?? "taskSession.actionSaveFailed"))
        }
        .task(model.load)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                model.refresh()
            }
        }
        .onDisappear(perform: onExit)
    }
}
