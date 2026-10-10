import SwiftUI

/// PIN解锁后的下一步；复用正式创建和提醒诊断，不保存另一套配置或绕过门控。
struct ParentSetupGuide: View {
    let hasTask: Bool
    let onCreate: () -> Void
    let onCheckReminders: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                hasTask ? "parentSetup.reminderTitle" : "parentSetup.taskTitle",
                systemImage: hasTask ? "bell" : "checklist")
        } description: {
            Text(hasTask ? "parentSetup.reminderDescription" : "parentSetup.taskDescription")
        } actions: {
            Button(
                hasTask ? "parentSetup.checkReminders" : "parentSetup.addTask",
                action: hasTask ? onCheckReminders : onCreate
            )
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .buttonStyle(MangaButtonStyle())
            .accessibilityIdentifier(hasTask ? "parent.setup.reminders" : "parent.setup.add-task")
        }
    }
}

#Preview("首用 · 添加 · MAX") {
    ParentSetupGuide(hasTask: false, onCreate: {}, onCheckReminders: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}
#Preview("首用 · 提醒 · 横屏") {
    ParentSetupGuide(hasTask: true, onCreate: {}, onCheckReminders: {}).frame(width: 900)
}
