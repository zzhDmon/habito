import SwiftUI

/// 家长今日列表行；状态同时使用图标和文字表达，不依赖颜色区分。
struct ParentTodayTaskRow: View {
    let item: TodayTaskItem
    let onReschedule: () -> Void
    let onSkip: () -> Void
    let onRestore: () -> Void
    let onCorrectAsCompleted: () -> Void

    var body: some View {
        HStack(spacing: HabitoDesign.Spacing.medium) {
            Image(systemName: item.iconName)
                .font(.title2)
                .frame(
                    minWidth: HabitoDesign.Layout.minimumTapSize,
                    minHeight: HabitoDesign.Layout.minimumTapSize
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
                Text(item.title)
                    .font(.headline)
                Text(item.scheduledAt, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if item.completion?.source == .parentCorrection {
                    Label("parentToday.parentCorrection", systemImage: "person.badge.checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: HabitoDesign.Spacing.small)

            Label(statusKey, systemImage: statusSymbol)
                .font(.subheadline)
                .foregroundStyle(statusStyle)

            if item.status == .pending || item.status == .skipped {
                Menu("parentToday.actions", systemImage: "ellipsis.circle") {
                    Button("parentToday.reschedule", systemImage: "clock", action: onReschedule)
                    if item.status == .pending {
                        Button("parentToday.skip", systemImage: "forward.end", action: onSkip)
                    } else {
                        Button(
                            "parentToday.restore",
                            systemImage: "arrow.uturn.backward",
                            action: onRestore
                        )
                    }
                    Button(
                        "parentToday.correctComplete",
                        systemImage: "checkmark.circle",
                        action: onCorrectAsCompleted
                    )
                }
                .frame(minWidth: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentTodayActions(item.id))
            }
        }
        .padding(.vertical, HabitoDesign.Spacing.small)
        .accessibilityIdentifier(HabitoAccessibilityID.parentTodayTask(item.id))
    }

    private var statusKey: LocalizedStringKey {
        switch item.status {
        case .pending: "parentToday.statusPending"
        case .inProgress: "parentToday.statusInProgress"
        case .completed: "parentToday.statusCompleted"
        case .skipped: "parentToday.statusSkipped"
        }
    }

    private var statusSymbol: String {
        switch item.status {
        case .pending: "clock"
        case .inProgress: "timer"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.end.fill"
        }
    }

    private var statusStyle: HierarchicalShapeStyle {
        item.status == .pending ? .secondary : .primary
    }
}
