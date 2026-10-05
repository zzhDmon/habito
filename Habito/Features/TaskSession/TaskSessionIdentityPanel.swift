import SwiftUI

/// 展示稳定任务身份和可读状态，不通过颜色独自表达等待或完成。
struct TaskSessionIdentityPanel: View {
    let task: KidTaskNavigationItem

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
            Image(systemName: task.iconName)
                .font(.system(.largeTitle, design: .rounded))
                .foregroundStyle(HabitoDesign.Palette.task)
                .accessibilityHidden(true)

            Text(task.title)
                .font(.largeTitle)
                .bold()

            Label(task.statusText, systemImage: task.statusIconName)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
    }
}

#Preview("任务身份 · 大字") {
    TaskSessionIdentityPanel(task: .previewReading)
        .environment(\.dynamicTypeSize, .accessibility3)
}
