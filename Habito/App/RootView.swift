import SwiftUI

/// V0 工程壳的根视图。
///
/// 当前只用于验证应用、导航和本地化资源能够正常加载；正式的孩子首页将在 M2 阶段接入。
struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("app.name", systemImage: "checkmark.circle")
            } description: {
                Text("app.placeholder")
            }
            .navigationTitle("app.name")
        }
    }
}

#Preview("iPad 横屏工程壳") {
    RootView()
}
