import Foundation
import Observation

/// MainActor 上的相机页面状态；只接收生命周期意图，不修改任务、计时或持久化数据。
@MainActor @Observable
final class TaskCameraViewModel {
    private(set) var state: FrontCameraState = .idle
    let previewSource: FrontCameraPreviewSource?
    @ObservationIgnored private let service: any FrontCameraCapturing
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var isEnabled = false

    init(service: any FrontCameraCapturing, previewSource: FrontCameraPreviewSource? = nil) {
        self.service = service
        self.previewSource = previewSource
    }

    /// 设置计时、场景和可见性合成后的意图；返回任务便于测试确定性等待，不依赖计时器。
    /// - Parameter enabled: 页面可见、场景激活、任务仍运行且未完成/待审核时为 true。
    /// - Returns: 最新异步更新；旧结果无权覆盖新的页面状态。
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Task<Void, Never> {
        isEnabled = enabled
        revision += 1
        let requestRevision = revision
        state = enabled ? .requestingPermission : .idle
        return Task { [service] in
            let result = await service.setEnabled(enabled, revision: requestRevision)
            guard requestRevision == revision else { return }
            state = result
        }
    }

    /// 场景激活不代表任务运行；待审核和完成快照必须关闭镜头，即使旧计时字段仍为 running。
    static func shouldCapture(state: TaskSessionViewState, isSceneActive: Bool) -> Bool {
        guard isSceneActive, case let .loaded(content) = state else { return false }
        return content.isRunning && content.completion == nil && !content.isAwaitingReview
    }

    func retry() { setEnabled(isEnabled) }

    /// 系统中断和运行错误不能继续显示“实时画面”；中断解除时只恢复仍有效的前台意图。
    func interrupted() { if isEnabled { state = .interrupted } }
    func failed() { if isEnabled { state = .failed } }
    func interruptionEnded() { if isEnabled { retry() } }
}
