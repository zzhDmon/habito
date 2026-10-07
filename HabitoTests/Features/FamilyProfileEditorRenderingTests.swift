import SwiftData
import SwiftUI
import Testing
@testable import Habito

/// 静态渲染仅检查自然换行，不能替代真实系统MAX输入/保存/滚动验收。
@MainActor
struct FamilyProfileEditorRenderingTests {
    @Test("所有名字反馈和保存栏在窄宽/横屏与MAX可渲染", arguments: [320, 900], [false, true])
    func saveBarRenders(width: Int, maximumTextSize: Bool) throws {
        let states: [FamilyProfileEditorFeedback?] = [
            nil, .saved, .storageFailure, .validation(.emptyChildNickname), .validation(.emptyPetName),
            .validation(.lineBreakInChildNickname), .validation(.lineBreakInPetName),
        ]
        for feedback in states {
            let renderer = ImageRenderer(
                content: FamilyProfileEditorSaveBar(feedback: feedback, isSaving: false, onSave: {})
                    .environment(\.dynamicTypeSize, maximumTextSize ? .accessibility5 : .large)
                    .frame(width: CGFloat(width)))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == width && image.height > 0)
        }
    }

    #if DEBUG
        @Test("一次读取失败参数必须同时有隔离测试开关", arguments: [false, true])
        func readProbeRequiresIsolation(enabled: Bool) throws {
            let context = try makeContext()
            let arguments =
                [UITestFamilyProfileEditorFactory.readFailureArgument]
                + (enabled ? [UITestLaunchConfiguration.enableArgument] : [])
            let model = UITestFamilyProfileEditorFactory.make(context: context, arguments: arguments)
            #expect(model.loadState == .idle && !context.hasChanges)
            model.load()
            #expect(model.loadState == (enabled ? .failed : .ready))
            model.retryLoad()
            #expect(model.loadState == .ready && model.childNickname.isEmpty)
            #expect(!context.hasChanges)
        }

        @Test("一次保存失败只在隔离开关下生效，回滚后可真实重试", arguments: [false, true])
        func saveProbeRequiresIsolationAndPreservesRetry(enabled: Bool) throws {
            let context = try makeContext()
            let arguments =
                [UITestFamilyProfileEditorFactory.saveFailureArgument]
                + (enabled ? [UITestLaunchConfiguration.enableArgument] : [])
            let model = UITestFamilyProfileEditorFactory.make(context: context, arguments: arguments)
            model.load()
            model.childNickname = "合成测试昵称"
            model.petName = "合成测试小狗"
            #expect(model.save() == !enabled)
            let service = FamilyProfileService(context: context)
            #expect((try service.load() != nil) == !enabled)
            #expect(!context.hasChanges)
            #expect(model.save())
            #expect(try service.load() == FamilyProfileNames(childNickname: "合成测试昵称", petName: "合成测试小狗"))
        }

        private func makeContext() throws -> ModelContext {
            ModelContext(try AppModelContainer.make(inMemory: true))
        }
    #endif
}
