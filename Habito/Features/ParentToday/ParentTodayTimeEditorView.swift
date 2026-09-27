import SwiftUI

/// 单日调时弹窗；只编辑时分，日期由原实例固定并由服务再次校验。
struct ParentTodayTimeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scheduledAt: Date
    private let item: TodayTaskItem
    private let onSave: (Date) -> Void

    init(item: TodayTaskItem, onSave: @escaping (Date) -> Void) {
        self.item = item
        self.onSave = onSave
        _scheduledAt = State(initialValue: item.scheduledAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "parentToday.timeLabel",
                    selection: $scheduledAt,
                    displayedComponents: .hourAndMinute
                )
                Text("parentToday.timeHelp")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(item.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("parentToday.cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("parentToday.saveTime", action: save)
                        .accessibilityIdentifier(HabitoAccessibilityID.parentTodayTimeSave)
                }
            }
        }
    }

    private func save() {
        onSave(scheduledAt)
        dismiss()
    }
}
