import SwiftUI

/// 展示当前完成事实；撤销剩余时间由页面值计算，重新进入不能延长窗口。
struct TaskCompletionSnapshotView: View {
    let completion: TodayTaskCompletion
    let undoRemainingSeconds: Int
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            Label("taskSession.completedTitle", systemImage: HabitoDesign.Symbol.completed)
                .font(.headline)
                .foregroundStyle(HabitoDesign.Palette.success)

            LabeledContent("taskSession.completedAt") {
                Text(completion.completedAt, style: .time)
            }

            LabeledContent(
                "taskSession.actualDuration",
                value: TaskSessionDurationText.spoken(completion.activeDurationSeconds)
            )

            if canUndo {
                Button(action: onUndo) {
                    Label {
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "taskSession.undoFormat"),
                                undoRemainingSeconds
                            )
                        )
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                    }
                    .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, HabitoDesign.Spacing.small)
                .accessibilityIdentifier(HabitoAccessibilityID.undoButton)
            }
        }
        .padding(.top, HabitoDesign.Spacing.small)
    }
}

#Preview("完成事实 · 撤销可达 · 大字") {
    TaskCompletionSnapshotView(
        completion: TodayTaskCompletion(
            id: UUID(), completedAt: .now, activeDurationSeconds: 780, source: .childManual),
        undoRemainingSeconds: 4, canUndo: true, onUndo: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("完成事实 · 撤销已过期") {
    TaskCompletionSnapshotView(
        completion: TodayTaskCompletion(
            id: UUID(), completedAt: .now, activeDurationSeconds: 780, source: .childManual),
        undoRemainingSeconds: 0, canUndo: false, onUndo: {}
    )
    .padding()
}
