import AVFoundation
import SwiftUI

/// 将系统视频预览放入 SwiftUI 小窗；不使用 SwiftUI 重绘每帧，也不取得视频帧数据。
struct TaskCameraPreview: UIViewRepresentable {
    let source: FrontCameraPreviewSource

    func makeUIView(context: Context) -> TaskCameraPreviewUIView {
        let view = TaskCameraPreviewUIView()
        if let layer = view.previewLayer {
            layer.videoGravity = .resizeAspectFill
            source.connect(to: layer)
        }
        view.isAccessibilityElement = true
        view.accessibilityLabel = String(localized: "taskCamera.previewLabel")
        return view
    }

    func updateUIView(_ view: TaskCameraPreviewUIView, context: Context) { view.updateOrientation() }

    static func dismantleUIView(_ view: TaskCameraPreviewUIView, coordinator: Void) {
        view.previewLayer?.session = nil
    }
}
