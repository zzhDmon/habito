import AVFoundation
import OSLog

/// AVFoundation 系统边界：阻塞式配置/启停放在 actor，避免冻结 SwiftUI 主线程。
///
/// 只添加前置视频输入和预览图层，不添加声音、照片或电影输出。会话随页面创建，离开时停止。
actor FrontCameraService: FrontCameraCapturing {
    nonisolated let previewSource = FrontCameraPreviewSource()
    private let permission: @Sendable () async -> FrontCameraState?
    private let captureOperation: (@Sendable (Bool) -> FrontCameraState)?

    /// 权限与采集替换点仅用于确定性测试；正式组合根使用系统权限和 actor 内会话。
    init(
        permission: @escaping @Sendable () async -> FrontCameraState? = FrontCameraService.systemPermission,
        captureOperation: (@Sendable (Bool) -> FrontCameraState)? = nil
    ) {
        self.permission = permission
        self.captureOperation = captureOperation
    }

    private var latestRevision: UInt64 = 0
    private var isConfigured = false
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "FrontCamera")

    func setEnabled(_ enabled: Bool, revision: UInt64) async -> FrontCameraState {
        guard revision >= latestRevision else { return .idle }
        latestRevision = revision
        guard enabled else {
            if let captureOperation { return captureOperation(false) }
            previewSource.withSession(isolation: self) { session in
                if session.isRunning { session.stopRunning() }
            }
            return .idle
        }

        let failure = await permission()
        // 授权跨越 await；暂停/退出会推进世代，旧授权结果没有启动相机的权限。
        guard revision == latestRevision, !Task.isCancelled else { return .idle }
        if let failure { return failure }
        if let captureOperation { return captureOperation(true) }
        return configureAndStart()
    }

    /// 请求视频权限，不请求麦克风；拒绝或系统限制保留明确状态供页面解释。
    nonisolated private static func systemPermission() async -> FrontCameraState? {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // 模拟器或无前置镜头的设备无需为不可用硬件弹出权限申请。
            guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil else {
                return .unavailable
            }
            return await AVCaptureDevice.requestAccess(for: .video) ? nil : .denied
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return nil
        @unknown default: return .restricted
        }
    }

    private func configureAndStart() -> FrontCameraState {
        previewSource.withSession(isolation: self) { session in
            if !isConfigured {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                else { return .unavailable }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    guard session.canAddInput(input) else { return .unavailable }
                    // 小窗无需高分辨率；减小采集成本，不影响任务计时精度。
                    if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
                    session.addInput(input)
                    isConfigured = true
                } catch {
                    logger.error("前置镜头配置失败：\(error.localizedDescription, privacy: .public)")
                    return .failed
                }
            }
            guard !session.isInterrupted else { return .interrupted }
            if !session.isRunning { session.startRunning() }
            return session.isRunning ? .running : .failed
        }
    }
}
