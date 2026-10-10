import AVFoundation
import SwiftUI

/// 计时页的紧凑镜头窗口；状态使用文字和图标表达，不让颜色成为唯一线索。
struct TaskCameraPanel: View {
    let state: FrontCameraState
    let source: FrontCameraPreviewSource?
    var onRetry: () -> Void = {}
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            Label("taskCamera.title", systemImage: "video.fill")
                .font(.headline)
            ZStack {
                Rectangle().fill(.black)
                if let source {
                    // 先连接预览图层再启动会话，保证采集图已有有效预览连接；暂停只隐藏画面，
                    // 不反复重建UIKit宿主。相机是否运行仍完全由服务控制，透明度不代替停机。
                    TaskCameraPreview(source: source)
                        .opacity(state == .running ? 1 : 0)
                        .accessibilityHidden(state != .running)
                        .accessibilityIdentifier("kid.session.camera-preview")
                }
                if state != .running {
                    Image(systemName: state == .idle ? "video.slash" : "person.crop.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: HabitoDesign.Camera.previewHeight)
            .clipShape(.rect(cornerRadius: HabitoDesign.Manga.corner))
            // 黑底占位图是装饰内容；给整个窗口明确语义，VoiceOver和UI测试才能发现它。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(state == .running ? "taskCamera.previewLabel" : "taskCamera.title"))
            .accessibilityIdentifier("kid.session.camera-window")
            // 状态文字在固定视频区域之外；辅助大字可以自然换行，不被180pt画面裁切。
            Label(LocalizedStringKey(state.messageKey), systemImage: state == .running ? "viewfinder" : "info.circle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("kid.session.camera-status")
            if state == .denied {
                Button("taskCamera.settings", systemImage: "gear", action: openSettings)
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            } else if state == .failed || state == .interrupted {
                Button("taskCamera.retry", systemImage: "arrow.clockwise", action: onRetry)
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            }
        }
        .frame(maxWidth: HabitoDesign.Camera.maximumWidth)
        .padding(HabitoDesign.Spacing.medium)
        .modifier(MangaPanel())
        // 容器必须独立成组，否则SwiftUI会把父标识传播给子元素并覆盖窗口/状态标识。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kid.session.camera-panel")
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview("镜头 · 未开始 · 横屏") {
    TaskCameraPanel(state: .idle, source: nil).frame(width: 380, height: 320)
}
#Preview("镜头 · 拒绝授权 · 辅助大字") {
    TaskCameraPanel(state: .denied, source: nil).environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("镜头 · 无设备 · 深色") {
    TaskCameraPanel(state: .unavailable, source: nil).preferredColorScheme(.dark)
}
