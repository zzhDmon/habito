import SwiftUI

/// 家长今日列表行；状态同时使用图标和文字表达，不依赖颜色区分。
struct ParentTodayTaskRow: View {
    let item: TodayTaskItem
    let onReschedule: () -> Void
    let onSkip: () -> Void
    let onRestore: () -> Void
    let onCorrectAsCompleted: () -> Void

    var body: some View {
        let presentation = ParentTodayTaskPresentation(item: item)
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
                Label {
                    Text(item.title)
                } icon: {
                    TaskIcon(storedName: item.iconName, compact: true)
                }
                .font(.headline)
                Text(item.scheduledAt, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let source = presentation.completionSourceKey {
                    Label(source, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let timing = presentation.completionTimingKey {
                    Label(timing, systemImage: "clock.badge.checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Label(presentation.statusKey, systemImage: presentation.statusSymbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if presentation.canManage {
                Menu {
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
                } label: {
                    Label("parentToday.actions", systemImage: "ellipsis.circle")
                        .frame(
                            minWidth: HabitoDesign.Layout.minimumTapSize, minHeight: HabitoDesign.Layout.minimumTapSize)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(HabitoAccessibilityID.parentTodayActions(item.id))
            }
        }
        .padding(.vertical, HabitoDesign.Spacing.small)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentTodayTask(item.id))
    }
}

#Preview("家长任务行 · 正常横屏", traits: .landscapeLeft) {
    if let item = ParentTodayTaskRow.previewItem(completed: false) {
        List {
            ParentTodayTaskRow(item: item, onReschedule: {}, onSkip: {}, onRestore: {}, onCorrectAsCompleted: {})
        }
    }
}

#Preview("家长任务行 · 完成MAX") {
    if let item = ParentTodayTaskRow.previewItem(completed: true) {
        List {
            ParentTodayTaskRow(item: item, onReschedule: {}, onSkip: {}, onRestore: {}, onCorrectAsCompleted: {})
        }.environment(\.dynamicTypeSize, .accessibility5)
    }
}

private extension ParentTodayTaskRow {
    /// 只为预览构造固定纯值；坏固定日期返回nil，不读取时钟或创建持久化容器。
    static func previewItem(completed: Bool) -> TodayTaskItem? {
        let date: LocalDate
        do { date = try LocalDate(dateKey: "2026-09-23") } catch { return nil }
        let time = Date(timeIntervalSince1970: 1_790_226_600)
        return TodayTaskItem(
            id: UUID(), date: date, scheduledAt: time, title: "固定合成阅读", iconName: "book.fill",
            colorToken: "reading", targetDurationSeconds: 900,
            status: completed ? .completed : .pending, origin: .generated(templateRevision: 1),
            activeSessionState: nil, activeDurationSeconds: 0,
            completion: completed
                ? TodayTaskCompletion(
                    id: UUID(), completedAt: time, activeDurationSeconds: 0,
                    source: .childManual, timing: .afterReminder) : nil)
    }
}
