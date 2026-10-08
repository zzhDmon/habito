import SwiftUI

/// 模板入口用可换行的按钮；大字号按单列排布，任务不会因浏览建议而被创建。
struct TaskPresetSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onApply: (TaskLearningPreset) -> Void

    var body: some View {
        Section {
            LazyVGrid(
                columns: dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140))]
            ) {
                ForEach(TaskLearningPreset.allCases, id: \.self) { preset in
                    Button {
                        onApply(preset)
                    } label: {
                        Text(LocalizedStringKey(preset.titleKey), tableName: "UIR1")
                            .frame(maxWidth: .infinity, minHeight: HabitoDesign.Layout.minimumTapSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("parent.templates.preset." + preset.rawValue)
                }
            }
        } header: {
            Text("taskPreset.section", tableName: "UIR1")
        } footer: {
            Text("taskPreset.hint", tableName: "UIR1")
        }
    }
}

#Preview("常用任务 · 最大字号") {
    Form { TaskPresetSection(onApply: { _ in }) }
        .environment(\.dynamicTypeSize, .accessibility5)
}
