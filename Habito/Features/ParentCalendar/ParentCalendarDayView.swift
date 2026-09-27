import SwiftUI

/// 家长按日查看任务实例并管理上课/放假覆盖的页面。
struct ParentCalendarDayView: View {
    @State private var model: ParentCalendarDayViewModel

    init(model: ParentCalendarDayViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section("parentCalendar.dateSection") {
                DatePicker(
                    "parentCalendar.selectedDate",
                    selection: $model.selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .onChange(of: model.selectedDate) { _, _ in model.load() }
            }

            if model.isLoading {
                ProgressView("parentCalendar.loading")
            } else if model.isLoadFailed {
                ContentUnavailableView {
                    Label("parentCalendar.errorTitle", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text("parentCalendar.errorDescription")
                } actions: {
                    Button("parentCalendar.retry", action: model.load)
                }
            } else if let snapshot = model.snapshot {
                ParentCalendarDayContent(snapshot: snapshot, onPreview: model.preview)
            }
        }
        .navigationTitle("parentCalendar.navigationTitle")
        .accessibilityIdentifier(HabitoAccessibilityID.parentCalendarScreen)
        .task(model.load)
        .confirmationDialog(
            confirmationTitle,
            isPresented: $model.isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("parentCalendar.confirm", role: confirmationRole) {
                model.confirmPendingAction()
            }
            .accessibilityIdentifier(HabitoAccessibilityID.parentCalendarConfirm)
            Button("parentCalendar.cancel", role: .cancel, action: model.cancelPendingAction)
        } message: {
            Text(impactDescription)
        }
        .alert("parentCalendar.actionErrorTitle", isPresented: $model.isActionErrorPresented) {
            Button("parentCalendar.dismiss", role: .cancel) {}
        } message: {
            Text("parentCalendar.actionErrorDescription")
        }
    }

    private var confirmationTitle: String {
        guard let impact = model.pendingImpact else { return "parentCalendar.noImpact" }
        switch impact.action {
        case .setSchoolDay: return String(localized: "parentCalendar.confirmSchoolDay")
        case .setHoliday: return String(localized: "parentCalendar.confirmHoliday")
        case .removeOverride: return String(localized: "parentCalendar.confirmRemove")
        }
    }

    private var confirmationRole: ButtonRole? {
        model.pendingImpact?.action == .setHoliday ? .destructive : nil
    }

    private var impactDescription: LocalizedStringKey {
        guard let impact = model.pendingImpact else { return "parentCalendar.noImpact" }
        return "parentCalendar.impact \(impact.insertedCount) \(impact.deletedCount) \(impact.protectedCount)"
    }
}
