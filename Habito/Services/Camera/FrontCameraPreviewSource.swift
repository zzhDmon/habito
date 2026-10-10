import AVFoundation

/// 仅把系统预览图层与采集会话连接起来，不暴露帧、不录制或保存人物画面。
///
/// - Important: AVCaptureSession 没有 Sendable 声明。这个不可变桥的 unchecked 承诺仅限
///   系统支持的图层连接：会话配置和启停始终属于 FrontCameraService actor；UI 只能在
///   MainActor 绑定/解绑预览。不得增加第二个可写会话的调用方。
nonisolated final class FrontCameraPreviewSource: @unchecked Sendable {
    fileprivate let session = AVCaptureSession()

    @MainActor
    func connect(to layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
    }

    @MainActor
    var notificationObject: AnyObject { session }

    /// 仅服务 actor 的同步代码使用；调用期间不包含 await，配置事务不会与启停交错。
    func withSession<Result>(isolation: isolated FrontCameraService, _ action: (AVCaptureSession) -> Result) -> Result {
        action(session)
    }
}
