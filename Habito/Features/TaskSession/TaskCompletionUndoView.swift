import SwiftUI

/// 五秒内的固定撤销入口，不要求孩子先滚过大字号庆祝内容。
///
/// 剩余秒数由注入时钟的页面快照提供；真正期限仍在动作服务校验，
/// 该组件只转发意图，不延长窗口或直接写账本。
struct TaskCompletionUndoView: View {
    let remainingSeconds: Int
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            Text("taskSession.undoRemaining \(remainingSeconds)")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier(HabitoAccessibilityID.undoButton)
        .padding(.horizontal, HabitoDesign.Spacing.large)
        .padding(.vertical, HabitoDesign.Spacing.small)
        .background(.regularMaterial)
    }
}

#Preview("固定撤销 · 横屏") {
    TaskCompletionUndoView(remainingSeconds: 5, onUndo: {}).frame(width: 900)
}

#Preview("固定撤销 · 最大字号") {
    TaskCompletionUndoView(remainingSeconds: 1, onUndo: {})
        .frame(width: 320).environment(\.dynamicTypeSize, .accessibility5)
}
