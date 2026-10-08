import SwiftUI

/// 模板列表行，同时用文字和图标表达启用状态。
struct ParentTaskTemplateRow: View {
    let item: ParentTaskTemplateListItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HabitoDesign.Spacing.medium) {
                TaskIcon(storedName: item.iconName)
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
                    .foregroundStyle(
                        item.lifecycleState == .active ? HabitoDesign.Manga.successInk : HabitoDesign.Manga.secondaryInk
                    )
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

#Preview("模板行 · 启用大字") {
    ParentTaskTemplateRow(
        item: ParentTaskTemplateListItem(
            id: UUID(), title: "阅读", iconName: "book.fill", targetDurationSeconds: 900, lifecycleState: .active,
            nextScheduledAt: nil, updatedAt: Date(timeIntervalSince1970: 1_790_064_000)), action: {}
    )
    .padding().environment(\.dynamicTypeSize, .accessibility5)
}
