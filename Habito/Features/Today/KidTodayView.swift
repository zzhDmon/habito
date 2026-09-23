import SwiftUI

/// 孩子打开 App 后看到的今日页基础结构。
struct KidTodayView: View {
    let tasks: [KidTaskNavigationItem]
    let onSelectTask: (KidTaskNavigationItem) -> Void

    var body: some View {
        AdaptiveTwoColumnLayout {
            KidTodayGreetingPanel()
        } trailing: {
            if let firstTask = tasks.first {
                VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
                    Label("kidToday.nextLabel", systemImage: "sparkles")
                        .font(.title2)
                        .bold()
                    KidTaskCard(task: firstTask) {
                        onSelectTask(firstTask)
                    }
                }
            } else {
                ContentUnavailableView(
                    "kidToday.emptyTitle",
                    systemImage: "sun.max.fill",
                    description: Text("kidToday.emptyDescription")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .navigationTitle("kidToday.navigationTitle")
        .background(.background)
    }
}

#Preview("今日 · iPad 横屏") {
    NavigationStack {
        KidTodayView(tasks: [.previewReading], onSelectTask: { _ in })
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 空态") {
    NavigationStack {
        KidTodayView(tasks: [], onSelectTask: { _ in })
    }
}

#Preview("今日 · 辅助功能字号") {
    NavigationStack {
        KidTodayView(tasks: [.previewReading], onSelectTask: { _ in })
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
