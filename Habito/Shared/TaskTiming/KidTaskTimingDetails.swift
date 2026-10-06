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
        .foregroundStyle(.secondary)
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
