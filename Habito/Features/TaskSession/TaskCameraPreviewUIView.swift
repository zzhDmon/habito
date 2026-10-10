import AVFoundation
import SwiftUI

/// UIKit 只承载 AVCaptureVideoPreviewLayer；SwiftUI 不能直接承载该 CALayer。
///
/// 生命周期属于 MainActor。连接使用当前 UIWindowScene 方向，支持 iPad 横屏左右旋转；
/// 不读取全局屏幕尺寸或依赖特定设备像素，系统布局变化时重新计算图层方向。
final class TaskCameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = previewLayer?.connection,
            let orientation = window?.windowScene?.interfaceOrientation
        else { return }
        let angle: CGFloat =
            switch orientation {
            case .landscapeLeft: 0
            case .landscapeRight: 180
            case .portraitUpsideDown: 270
            default: 90
            }
        // videoRotationAngle 从 iPadOS 17 起可用；无需已弃用的 videoOrientation。
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
