import SwiftUI

/// 家长显式选择任务语义；分类和时间段不会推导或改写提醒、验收与奖励。
struct TaskTemplateConfigurationSection: View {
    @Binding var draft: TaskTemplateDraft

    var body: some View {
        Section {
            Picker("taskEditor.category", selection: $draft.category) {
                ForEach(TaskCategory.allCases, id: \.self) { value in
                    // 先构造完整 String 键，避免 SwiftUI 将插值当作翻译占位符。
                    Text(LocalizedStringKey("taskEditor.category." + value.rawValue)).tag(value)
                }
            }
            // Form 的菜单样式在新系统只暴露矮的内层按钮；导航选择使用整行原生命中区域。
            .pickerStyle(.navigationLink)
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .accessibilityIdentifier(HabitoAccessibilityID.taskEditorCategory)
            Picker("taskEditor.timePeriod", selection: $draft.timePeriod) {
                ForEach(TaskTimePeriod.allCases, id: \.self) { value in
                    Text(LocalizedStringKey("taskEditor.timePeriod." + value.rawValue)).tag(value)
                }
            }
            .pickerStyle(.navigationLink)
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .accessibilityIdentifier(HabitoAccessibilityID.taskEditorTimePeriod)
            Picker("taskEditor.verification", selection: $draft.verificationType) {
                ForEach(TaskVerificationType.allCases, id: \.self) { value in
                    Text(LocalizedStringKey("taskEditor.verification." + value.rawValue)).tag(value)
                }
            }
            .pickerStyle(.navigationLink)
            .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
            .accessibilityIdentifier(HabitoAccessibilityID.taskEditorVerification)
        } header: {
            Text("taskEditor.configurationSection")
        } footer: {
            Text("taskEditor.configurationHint")
        }
    }
}

#Preview("旧任务 · 待设置") {
    @Previewable @State var draft = TaskTemplateDraft.new
    NavigationStack {
        Form { TaskTemplateConfigurationSection(draft: $draft) }
    }
}

#Preview("家长验收 · 最大字号") {
    @Previewable @State var draft = {
        var value = TaskTemplateDraft.new
        value.category = .growth
        value.timePeriod = .evening
        value.verificationType = .parentApproval
        return value
    }()
    NavigationStack {
        Form { TaskTemplateConfigurationSection(draft: $draft) }
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
