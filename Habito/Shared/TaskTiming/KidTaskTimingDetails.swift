import SwiftUI

/// 推荐卡、任务行和执行页共用的时间文字；不通过颜色独自表达截止提示。
struct KidTaskTimingDetails: View {
    let presentation: KidTaskTimingPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
            Text(verbatim: presentation.reminderText)
                .accessibilityIdentifier(HabitoAccessibilityID.taskReminderTime(presentation.taskID))
            if let plannedText = presentation.plannedText {
                Text(verbatim: plannedText)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskPlannedTime(presentation.taskID))
            }
            if let deadlineText = presentation.deadlineText {
                Text(verbatim: deadlineText)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskDeadlineTime(presentation.taskID))
            }
            if presentation.showsDeadlineHint {
                Label("kidTask.deadlinePassedHint", systemImage: "clock")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(HabitoAccessibilityID.taskDeadlineHint(presentation.taskID))
            }
        }
        .font(.subheadline)
        // 漫画纸底使用已验收的不透明次要墨色；系统层级透明色叠加后可能过淡。
        .foregroundStyle(HabitoDesign.Manga.secondaryInk)
    }
}

#Preview("时间 · 旧任务没有计划和截止") {
    KidTaskTimingDetails(presentation: .preview(for: .previewReading)).padding()
}

#Preview("时间 · 三时间与温和截止提示 · 最大字号") {
    KidTaskTimingDetails(presentation: .preview(for: .previewThreeTimes))
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
