import SwiftUI

/// PIN后才创建的名字设置页面；持久化由注入的页面状态转发，不在View编排写入。
struct FamilyProfileEditorView: View {
    @State private var model: FamilyProfileEditorViewModel
    /// 焦点随页面生灭并归属主actor；保存前结束编辑，避免键盘遮住真实反馈。
    @FocusState private var focusedField: String?
    private let onClose: () -> Void

    init(model: FamilyProfileEditorViewModel, onClose: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onClose = onClose
    }

    var body: some View {
        @Bindable var model = model

        Group {
            switch model.loadState {
            case .idle:
                ProgressView("familyProfile.loading")
            case .failed:
                ContentUnavailableView {
                    Label("familyProfile.loadErrorTitle", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("familyProfile.loadErrorDescription")
                } actions: {
                    Button("familyProfile.retry", action: model.retryLoad)
                        .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                        .accessibilityIdentifier(HabitoAccessibilityID.familyProfileRetry)
                }
                // 先建立容器边界，否则外层identifier会覆盖原生重试按钮的独立标识。
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(HabitoAccessibilityID.familyProfileLoadError)
            case .ready:
                FamilyProfileEditorForm(
                    childNickname: $model.childNickname, petName: $model.petName,
                    focus: $focusedField, hasStoredNames: model.hasStoredNames
                )
                .safeAreaInset(edge: .bottom) {
                    FamilyProfileEditorSaveBar(
                        feedback: model.feedback, isSaving: model.isSaving, onSave: save)
                }
            }
        }
        .navigationTitle("familyProfile.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 此动作由家长sheet注入；页面自己的dismiss只会返回列表，不会关闭整个门禁。
                Button("parentGate.close", action: onClose)
                    .frame(minWidth: HabitoDesign.Layout.minimumTapSize, minHeight: HabitoDesign.Layout.minimumTapSize)
                    .accessibilityIdentifier(HabitoAccessibilityID.parentClose)
            }
        }
        .task(model.load)
        // 返回或关闭均撤下内存草稿；未保存不自动写入，再进入显式读取最新资料。
        .onDisappear(perform: model.reset)
    }

    private func save() {
        focusedField = nil
        model.save()
    }
}

#Preview("未设置／横屏", traits: .landscapeLeft) {
    NavigationStack {
        FamilyProfileEditorView(model: FamilyProfileEditorViewModel(loadNames: { nil }, saveNames: { _ in true }))
    }
}

#Preview("已有名字／最大字号", traits: .landscapeLeft) {
    NavigationStack {
        FamilyProfileEditorView(
            model: FamilyProfileEditorViewModel(
                loadNames: { try FamilyProfileNames(childNickname: "合成昵称", petName: "合成小狗") },
                saveNames: { _ in false }))
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("载入失败／可重试", traits: .landscapeLeft) {
    NavigationStack {
        FamilyProfileEditorView(
            model: FamilyProfileEditorViewModel(
                loadNames: { throw FamilyProfileServiceError.invalidStoredNames }, saveNames: { _ in false }))
    }
}
