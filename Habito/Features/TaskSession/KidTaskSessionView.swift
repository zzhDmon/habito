import AVFoundation
import SwiftUI

/// 任务执行页容器，负责持有页面模型并响应 App 场景恢复。
struct KidTaskSessionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraModel: TaskCameraViewModel
    @State private var model: TaskSessionViewModel
    private let onExit: () -> Void

    init(model: TaskSessionViewModel, cameraModel: TaskCameraViewModel, onExit: @escaping () -> Void) {
        _cameraModel = State(initialValue: cameraModel)
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
                    cameraModel: cameraModel,
                    content: content,
                    snoozeState: model.snoozeState,
                    onStartOrResume: model.startOrResume,
                    onPause: model.pause,
                    onSnooze: model.snooze,
                    onComplete: model.completeTask,
                    onUndoCompletion: model.undoCompletion,
                    currentDate: model.currentDate,
                    makeTimingPresentation: model.makeTimingPresentation,
                    completionFeedback: model.completionFeedback,
                    onDismissCompletionFeedback: model.dismissCompletionFeedback
                )
            case .failed:
                ContentUnavailableView {
                    Label("taskSession.errorTitle", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text("taskSession.errorDescription")
                } actions: {
                    Button("taskSession.retry", action: model.load)
                        .buttonStyle(MangaButtonStyle())
                        .controlSize(.large)
                }
            }
        }
        .navigationTitle("kidTask.navigationTitle")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(HabitoDesign.Manga.ink)
        .tint(HabitoDesign.Manga.successInk)
        .background(HabitoDesign.Manga.paper)
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
        .onChange(of: shouldCapture, initial: true) { _, enabled in cameraModel.setEnabled(enabled) }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVCaptureSession.wasInterruptedNotification, object: cameraModel.previewSource?.notificationObject)
        ) { _ in Task { @MainActor in cameraModel.interrupted() } }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVCaptureSession.interruptionEndedNotification,
                object: cameraModel.previewSource?.notificationObject)
        ) { _ in Task { @MainActor in cameraModel.interruptionEnded() } }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVCaptureSession.runtimeErrorNotification, object: cameraModel.previewSource?.notificationObject)
        ) { _ in Task { @MainActor in cameraModel.failed() } }
        .onDisappear(perform: exit)
    }

    /// 只把已保存页面事实合成生命周期意图；不把相机状态反写为计时状态。
    private var shouldCapture: Bool {
        TaskCameraViewModel.shouldCapture(state: model.state, isSceneActive: scenePhase == .active)
    }

    private func exit() {
        cameraModel.setEnabled(false)
        onExit()
    }
}
