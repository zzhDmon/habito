import SwiftUI

/// V0 工程壳的根视图和当前开发探针入口。
struct RootView: View {
    let notificationProbeModel: NotificationProbeViewModel

    var body: some View {
        NavigationStack {
            NotificationProbeView(model: notificationProbeModel)
        }
    }
}

#Preview("iPad 横屏工程壳") {
    RootView(
        notificationProbeModel: NotificationProbeViewModel(
            notificationService: LocalNotificationService()
        )
    )
}
