import SwiftUI

/// 家长中心的任务模板列表、空态和错误态。
struct ParentTaskTemplateListView: View {
    @State private var model: ParentTaskTemplateListViewModel
    let onShowReview: () -> Void
    let onShowToday: () -> Void
    let onShowCalendar: () -> Void
    let onShowNotifications: () -> Void
    let onCreate: () -> Void
    let onSelect: (UUID) -> Void

    init(
        model: ParentTaskTemplateListViewModel,
        onShowReview: @escaping () -> Void,
        onShowToday: @escaping () -> Void,
        onShowCalendar: @escaping () -> Void,
        onShowNotifications: @escaping () -> Void,
        onCreate: @escaping () -> Void,
        onSelect: @escaping (UUID) -> Void
    ) {
        _model = State(initialValue: model)
        self.onShowReview = onShowReview
        self.onShowToday = onShowToday
        self.onShowCalendar = onShowCalendar
        self.onShowNotifications = onShowNotifications
        self.onCreate = onCreate
        self.onSelect = onSelect
    }

    var body: some View {
        ParentTaskTemplateListContent(
            state: model.state,
            onCreate: onCreate,
            onSelect: onSelect,
            onRetry: model.load
        )
        .safeAreaInset(edge: .top) {
            Button("parentReview.open", systemImage: "checkmark.seal", action: onShowReview)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                .padding(.horizontal, HabitoDesign.Spacing.medium)
                .padding(.vertical, HabitoDesign.Spacing.small)
                .background(.bar)
                .accessibilityIdentifier(HabitoAccessibilityID.parentReviewOpen)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("parentToday.open", systemImage: "list.bullet", action: onShowToday)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentTodayOpen)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("parentCalendar.open", systemImage: "calendar", action: onShowCalendar)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentCalendarOpen)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("notification.diagnosticsOpen", systemImage: "bell.badge", action: onShowNotifications)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentNotificationDiagnosticsOpen)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("parentTemplates.create", systemImage: "plus", action: onCreate)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentTemplateCreate)
            }
        }
        // 新增 safeAreaInset 按钮不能继承外层标识，否则会覆盖它的独立审核入口 identifier。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentUnlocked)
        .task(model.load)
    }
}
