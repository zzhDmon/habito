import SwiftUI

/// 家长中心的任务模板列表、空态和错误态。
struct ParentTaskTemplateListView: View {
    @State private var showsManagement = false
    @State private var model: ParentTaskTemplateListViewModel
    let onShowReview: () -> Void
    let onShowStatistics: () -> Void
    let onShowFamilyProfile: () -> Void
    let onShowToday: () -> Void
    let onShowCalendar: () -> Void
    let onShowNotifications: () -> Void
    let onCreate: () -> Void
    let onSelect: (UUID) -> Void

    init(
        model: ParentTaskTemplateListViewModel,
        onShowReview: @escaping () -> Void,
        onShowStatistics: @escaping () -> Void = {},
        onShowFamilyProfile: @escaping () -> Void = {},
        onShowToday: @escaping () -> Void,
        onShowCalendar: @escaping () -> Void,
        onShowNotifications: @escaping () -> Void,
        onCreate: @escaping () -> Void,
        onSelect: @escaping (UUID) -> Void
    ) {
        _model = State(initialValue: model)
        self.onShowReview = onShowReview
        self.onShowStatistics = onShowStatistics
        self.onShowFamilyProfile = onShowFamilyProfile
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
            onRetry: model.load,
            showsSetupGuide: model.showsSetupGuide,
            setupHasTask: model.setupHasTask,
            onCheckReminders: checkSetupReminders
        )
        .safeAreaInset(edge: .top) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: HabitoDesign.Spacing.medium) {
                    todayButton
                    reviewButton
                }
                VStack(spacing: HabitoDesign.Spacing.small) {
                    todayButton
                    reviewButton
                }
            }
            .padding(.horizontal, HabitoDesign.Spacing.medium)
            .padding(.vertical, HabitoDesign.Spacing.small)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("parentHub.more", systemImage: "ellipsis.circle", action: openManagement)
                    .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                    .accessibilityIdentifier("parent.hub.more")
                    .popover(isPresented: $showsManagement) {
                        ParentManagementMenu(
                            onStatistics: showStatistics, onCalendar: showCalendar,
                            onProfile: showProfile, onNotifications: showNotifications)
                    }

            }
            ToolbarItem(placement: .primaryAction) {
                Button("parentTemplates.create", systemImage: "plus", action: onCreate)
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentTemplateCreate)
            }
        }
        // 新增 safeAreaInset 按钮不能继承外层标识，否则会覆盖它的独立审核入口 identifier。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentUnlocked)
        .task(model.load)
    }
    private func openManagement() { showsManagement = true }
    private func checkSetupReminders() { model.finishSetupGuide(); onShowNotifications() }
    private func showStatistics() { showsManagement = false; onShowStatistics() }
    private func showCalendar() { showsManagement = false; onShowCalendar() }
    private func showProfile() { showsManagement = false; onShowFamilyProfile() }
    private func showNotifications() { showsManagement = false; onShowNotifications() }

    // 两个同等常用入口共享紧凑结构；其余管理功能在菜单内，不占据任务列表高度。
    private var todayButton: some View {
        Button("parentToday.open", systemImage: "list.bullet", action: onShowToday)
            .buttonStyle(.bordered)
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .accessibilityIdentifier(HabitoAccessibilityID.parentTodayOpen)
    }

    private var reviewButton: some View {
        Button("parentReview.open", systemImage: "checkmark.seal", action: onShowReview)
            .buttonStyle(.borderedProminent)
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .accessibilityIdentifier(HabitoAccessibilityID.parentReviewOpen)
    }

}
