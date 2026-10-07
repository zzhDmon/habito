import SwiftUI

/// 家长查看和纠正当天全部任务实例的页面。
struct ParentTodayTaskListView: View {
    @State private var model: ParentTodayTaskViewModel
    @State private var timeEditingItem: TodayTaskItem?
    let onShowStatistics: () -> Void

    init(model: ParentTodayTaskViewModel, onShowStatistics: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onShowStatistics = onShowStatistics
    }

    var body: some View {
        @Bindable var model = model

        ParentTodayTaskListBody(
            state: model.state,
            onReschedule: { timeEditingItem = $0 },
            onSkip: model.skip,
            onRestore: model.restore,
            onCorrectAsCompleted: model.correctAsCompleted,
            onRetry: model.load,
            overviewState: model.overviewModel?.state ?? .idle,
            onRetryOverview: model.load,
            onShowStatistics: onShowStatistics
        )
        .navigationTitle("parentToday.navigationTitle")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentTodayScreen)
        .task(model.load)
        .sheet(item: $timeEditingItem) { item in
            ParentTodayTimeEditorView(item: item) { scheduledAt in
                model.reschedule(occurrenceID: item.id, to: scheduledAt)
            }
        }
        .alert("parentToday.actionErrorTitle", isPresented: $model.isActionErrorPresented) {
            Button("parentToday.dismiss", role: .cancel) {}
        } message: {
            Text("parentToday.actionErrorDescription")
        }
    }
}
