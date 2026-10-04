import SwiftUI

/// 展示应用侧核对结果；系统实际送达仍需真机观察，不能由排程数量推断。
struct NotificationSchedulingStatusView: View {
    let state: NotificationRebuildState
    let onRetry: () -> Void

    var body: some View {
        Section {
            switch state {
            case .idle:
                Text("notification.schedulingUnchecked")
            case .rebuilding:
                ProgressView("notification.schedulingChecking")
            case let .completed(result, checkedAt):
                if result.authorization.canSchedule {
                    LabeledContent("notification.schedulingPrimaryCount") {
                        Text(result.selection.primaryCandidates.count, format: .number)
                            .accessibilityIdentifier(HabitoAccessibilityID.notificationPrimaryCount)
                    }
                    LabeledContent("notification.schedulingSnoozeCount") {
                        Text(result.scheduledSnoozeCount, format: .number)
                    }
                    if result.selection.primaryCandidates.isEmpty && result.scheduledSnoozeCount == 0 {
                        Text("notification.schedulingNoTasks")
                    } else {
                        LabeledContent("notification.schedulingCoverage") {
                            Text(result.selection.coverageThrough.dateKey)
                        }
                        if result.selection.isCoverageBoundaryPartial {
                            Label("notification.schedulingPartialDay", systemImage: "exclamationmark.triangle")
                        }
                        if !result.selection.hasMinimumCoverage {
                            Label("notification.schedulingLimitedCoverage", systemImage: "exclamationmark.triangle")
                        }
                    }
                } else {
                    Label("notification.schedulingDisabled", systemImage: "bell.slash")
                }
                LabeledContent("notification.schedulingCheckedAt") {
                    Text(checkedAt, format: .dateTime.month().day().hour().minute())
                }
            case .failed:
                Label("notification.schedulingFailed", systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier(HabitoAccessibilityID.notificationSchedulingError)
            }
            Button("notification.schedulingRetry", systemImage: "arrow.clockwise", action: onRetry)
                .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                .disabled(state == .rebuilding)
                .accessibilityIdentifier(HabitoAccessibilityID.notificationSchedulingRetry)
        } header: {
            Text("notification.schedulingTitle")
        } footer: {
            Text("notification.schedulingFooter")
        }
    }
}

#Preview("排程失败 · 横屏", traits: .landscapeLeft) {
    Form { NotificationSchedulingStatusView(state: .failed, onRetry: {}) }
}

#Preview("排程未检查 · 大字号", traits: .landscapeLeft) {
    Form { NotificationSchedulingStatusView(state: .idle, onRetry: {}) }
        .environment(\.dynamicTypeSize, .accessibility3)
}
