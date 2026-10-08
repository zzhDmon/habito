import SwiftUI

/// 已安排只是系统队列写入成功，不承诺实际送达；权限/预算等失败分别说明。
struct TaskSnoozeFeedbackView: View {
    let state: TaskSnoozeState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .scheduling:
            Label("taskSession.snoozeScheduling", systemImage: "clock")
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)
        case .scheduled:
            Label("taskSession.snoozeScheduled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(HabitoDesign.Manga.successInk)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .crossesMidnight:
            Label("taskSession.snoozeMidnight", systemImage: "moon.stars.fill")
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .budgetFull:
            Label("taskSession.snoozeBudgetFull", systemImage: "bell.slash.fill")
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .unavailable:
            Label("taskSession.snoozeUnavailable", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .failed:
            Label("taskSession.snoozeFailed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        case .notificationsDisabled:
            Label("taskSession.snoozeNotificationsDisabled", systemImage: "bell.slash.fill")
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                .accessibilityIdentifier(HabitoAccessibilityID.snoozeFeedback)
        }
    }
}

#Preview("稍后反馈 · 成功与失败 · 大字") {
    VStack(alignment: .leading) {
        TaskSnoozeFeedbackView(state: .scheduled(.now))
        TaskSnoozeFeedbackView(state: .failed)
        TaskSnoozeFeedbackView(state: .notificationsDisabled)
        TaskSnoozeFeedbackView(state: .idle)
    }
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}
