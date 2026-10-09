import SwiftUI

/// Form 中整行可点击的展开按钮；内容由调用方作为独立表单行呈现，避免输入节点被折叠组吞并。
struct TaskEditorDisclosureButton<Content: View>: View {
    @Binding var isExpanded: Bool
    let identifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: HabitoDesign.Spacing.small) {
                content()
                Spacer(minLength: HabitoDesign.Spacing.small)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "taskEditor.expanded" : "taskEditor.collapsed")
        .accessibilityIdentifier(identifier)
    }

    private func toggle() { isExpanded.toggle() }
}

#Preview("整行展开 · MAX") {
    @Previewable @State var expanded = false
    Form {
        TaskEditorDisclosureButton(isExpanded: $expanded, identifier: "preview.section") {
            Text("taskEditor.customWeekdays")
        }
    }.environment(\.dynamicTypeSize, .accessibility5)
}
