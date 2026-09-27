import SwiftUI

/// 模板列表行，同时用文字和图标表达启用状态。
struct ParentTaskTemplateRow: View {
    let item: ParentTaskTemplateListItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                    Text(durationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    nextPlan
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: HabitoDesign.Spacing.small)

                Label(statusKey, systemImage: statusSymbol)
                    .font(.subheadline)
                    .foregroundStyle(item.lifecycleState == .active ? .green : .secondary)
            }
            .padding(.vertical, HabitoDesign.Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
        .accessibilityIdentifier(HabitoAccessibilityID.parentTemplate(item.id))
        .accessibilityHint("parentTemplates.openHint")
    }

    @ViewBuilder
    private var nextPlan: some View {
        if item.lifecycleState != .active {
            Text("parentTemplates.nextDisabled")
        } else if let date = item.nextScheduledAt {
            let prefix = Text("parentTemplates.nextPrefix")
            let value = Text(
                date,
                format: .dateTime.month().day().weekday(.abbreviated).hour().minute()
            )
            Text("\(prefix)\(value)")
        } else {
            Text("parentTemplates.nextNone")
        }
    }

    private var durationText: String {
        let minutes = max(1, Int(ceil(item.targetDurationSeconds / 60)))
        return String.localizedStringWithFormat(
            String(localized: "kidTask.durationMinutesFormat"),
            minutes
        )
    }

    private var statusKey: LocalizedStringKey {
        item.lifecycleState == .active ? "parentTemplates.enabled" : "parentTemplates.disabled"
    }

    private var statusSymbol: String {
        item.lifecycleState == .active ? "checkmark.circle.fill" : "pause.circle.fill"
    }
}
