import Foundation
import SwiftUI
import Testing
@testable import Habito

@MainActor
@Suite("任务前置镜头生命周期")
struct TaskCameraViewModelTests {
    @Test("授权弹窗期间暂停或离开，授权返回不能重新打开镜头")
    func stopDuringPermissionDoesNotStartCamera() async {
        let gate = CameraPermissionGate()
        let probe = CameraCaptureProbe()
        let service = FrontCameraService(permission: { await gate.request() }, captureOperation: probe.capture)
        let model = TaskCameraViewModel(service: service)
        let opening = model.setEnabled(true)
        await gate.waitUntilRequested()
        #expect(model.state == .requestingPermission)
        await model.setEnabled(false).value
        await gate.resolve()
        await opening.value
        #expect(model.state == .idle)
        #expect(probe.requests == [false])
    }

    @Test("拒绝或系统限制不调用采集硬件", arguments: [FrontCameraState.denied, .restricted])
    func permissionFailureDoesNotCapture(failure: FrontCameraState) async {
        let probe = CameraCaptureProbe()
        let model = TaskCameraViewModel(
            service: FrontCameraService(permission: { failure }, captureOperation: probe.capture))
        await model.setEnabled(true).value
        #expect(model.state == failure)
        #expect(probe.requests.isEmpty)
        await model.setEnabled(false).value
        #expect(model.state == .idle)
    }

    @Test("无设备或启动失败反馈独立于计时", arguments: [FrontCameraState.unavailable, .failed])
    func hardwareFailureIsVisible(failure: FrontCameraState) async {
        let probe = CameraCaptureProbe(result: failure)
        let model = TaskCameraViewModel(
            service: FrontCameraService(permission: { nil }, captureOperation: probe.capture))
        await model.setEnabled(true).value
        #expect(model.state == failure)
        #expect(probe.requests == [true])
    }

    @Test("后台关闭后回前台恢复，系统中断不能误报实时画面")
    func backgroundAndInterruptionRespectLatestIntent() async {
        let probe = CameraCaptureProbe()
        let model = TaskCameraViewModel(
            service: FrontCameraService(permission: { nil }, captureOperation: probe.capture))
        await model.setEnabled(true).value
        #expect(model.state == .running)
        model.interrupted()
        #expect(model.state == .interrupted)
        await model.setEnabled(false).value
        model.interruptionEnded()
        model.failed()
        #expect(model.state == .idle)
        await model.setEnabled(true).value
        #expect(model.state == .running)
        #expect(probe.requests == [true, false, true])
    }

    @Test("旧关闭意图不得停止新会话")
    func staleStopCannotStopNewerCapture() async {
        let probe = CameraCaptureProbe()
        let service = FrontCameraService(permission: { nil }, captureOperation: probe.capture)
        #expect(await service.setEnabled(true, revision: 3) == .running)
        #expect(await service.setEnabled(false, revision: 2) == .idle)
        #expect(probe.requests == [true])
    }

    @Test("取消授权等待不能开启硬件")
    func cancelledPermissionRequestDoesNotCapture() async {
        let gate = CameraPermissionGate()
        let probe = CameraCaptureProbe()
        let service = FrontCameraService(permission: { await gate.request() }, captureOperation: probe.capture)
        let opening = Task { await service.setEnabled(true, revision: 1) }
        await gate.waitUntilRequested()
        opening.cancel()
        await gate.resolve()
        #expect(await opening.value == .idle)
        #expect(probe.requests.isEmpty)
    }

    @Test("连续开始暂停继续只保留最新运行意图")
    func rapidTimerChangesKeepLatestIntent() async {
        let probe = CameraCaptureProbe()
        let model = TaskCameraViewModel(
            service: FrontCameraService(permission: { nil }, captureOperation: probe.capture))
        let opening = model.setEnabled(true)
        let stopping = model.setEnabled(false)
        let resuming = model.setEnabled(true)
        await opening.value
        await stopping.value
        await resuming.value
        #expect(model.state == .running)
        #expect(probe.requests.last == true)
        await model.setEnabled(false).value
        #expect(model.state == .idle)
        #expect(probe.requests.last == false)
    }

    @Test("小窗普通及最大字号错误文案可以自然增长", arguments: [FrontCameraState.idle, .denied, .failed, .unavailable], [false, true])
    func cameraStatusRendersWithoutFixedTextHeight(state: FrontCameraState, maximumTextSize: Bool) throws {
        let renderer = ImageRenderer(
            content: TaskCameraPanel(state: state, source: nil)
                .environment(\.dynamicTypeSize, maximumTextSize ? .accessibility5 : .large)
                .frame(width: 320))
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320)
        #expect(image.height > 180)
    }

    @Test("只有运行中前台页面需要镜头，暂停完成待审核和加载错误均关闭")
    func lifecycleEligibilityUsesSavedTaskFacts() {
        func content(
            timer: TimerSessionState? = .running, completion: TodayTaskCompletion? = nil,
            submission: TaskSubmissionSnapshot? = nil
        ) -> TaskSessionScreenContent {
            TaskSessionScreenContent(
                task: .previewReading, targetDurationSeconds: 900,
                activeSessionState: timer, activeDurationAtSnapshot: 0,
                snapshotAt: Date(timeIntervalSince1970: 100), completion: completion, submission: submission)
        }
        #expect(TaskCameraViewModel.shouldCapture(state: .loaded(content()), isSceneActive: true))
        #expect(!TaskCameraViewModel.shouldCapture(state: .loaded(content()), isSceneActive: false))
        #expect(!TaskCameraViewModel.shouldCapture(state: .loaded(content(timer: .paused)), isSceneActive: true))
        #expect(!TaskCameraViewModel.shouldCapture(state: .loaded(content(timer: nil)), isSceneActive: true))
        let completion = TodayTaskCompletion(
            id: UUID(), completedAt: Date(timeIntervalSince1970: 100),
            activeDurationSeconds: 20, source: .childManual)
        #expect(
            !TaskCameraViewModel.shouldCapture(state: .loaded(content(completion: completion)), isSceneActive: true))
        let submission = TaskSubmissionSnapshot(
            id: UUID(), submittedAt: Date(timeIntervalSince1970: 100),
            state: .waiting, reviewedAt: nil, timing: .beforeReminder, activeDurationSeconds: 20, expectedXP: 0,
            expectedCoins: 0)
        #expect(
            !TaskCameraViewModel.shouldCapture(state: .loaded(content(submission: submission)), isSceneActive: true))
        #expect(!TaskCameraViewModel.shouldCapture(state: .loading, isSceneActive: true))
        #expect(!TaskCameraViewModel.shouldCapture(state: .failed, isSceneActive: true))
    }
}
