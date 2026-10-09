import SwiftUI

/// 自适应字号的管理菜单；显式提供44pt以上整行命中区，避免系统菜单的窄行限制。
struct ParentManagementMenu: View {
    let onStatistics: () -> Void
    let onCalendar: () -> Void
    let onProfile: () -> Void
    let onNotifications: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
                Button(action: onStatistics) {
                    Label("statistics.open", systemImage: "chart.bar")
                        .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
                        .contentShape(Rectangle())
                }.accessibilityIdentifier(HabitoAccessibilityID.statisticsOpen)
                Button(action: onCalendar) {
                    Label("parentCalendar.open", systemImage: "calendar")
                        .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
                        .contentShape(Rectangle())
                }.accessibilityIdentifier(HabitoAccessibilityID.parentCalendarOpen)
                Button(action: onProfile) {
                    Label("familyProfile.title", systemImage: "person.and.background.dotted")
                        .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
                        .contentShape(Rectangle())
                }.accessibilityIdentifier(HabitoAccessibilityID.familyProfileOpen)
                Button(action: onNotifications) {
                    Label("notification.diagnosticsOpen", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
                        .contentShape(Rectangle())
                }.accessibilityIdentifier(HabitoAccessibilityID.parentNotificationDiagnosticsOpen)
            }
            .buttonStyle(.plain)
            .padding(HabitoDesign.Spacing.medium)
        }
        .frame(idealWidth: HabitoDesign.Layout.columnMinimumWidth, idealHeight: HabitoDesign.Layout.columnMinimumWidth)
    }
}

#Preview("管理菜单 · 大字") {
    ParentManagementMenu(onStatistics: {}, onCalendar: {}, onProfile: {}, onNotifications: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}
