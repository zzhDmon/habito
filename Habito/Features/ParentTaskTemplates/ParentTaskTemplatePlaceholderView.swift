import SwiftUI

/// M3-002 用于证明新建和详情入口可达的占位页；M3-003 将替换为真实编辑器。
struct ParentTaskTemplatePlaceholderView: View {
    let route: ParentTaskTemplateRoute

    var body: some View {
        ContentUnavailableView(
            titleKey,
            systemImage: "slider.horizontal.3",
            description: Text("parentTemplates.editorPlaceholderDescription")
        )
        .navigationTitle(titleKey)
        .accessibilityIdentifier(HabitoAccessibilityID.parentTemplateDestination)
    }

    private var titleKey: LocalizedStringKey {
        switch route {
        case .create: "parentTemplates.createTitle"
        case .detail: "parentTemplates.detailTitle"
        }
    }
}
