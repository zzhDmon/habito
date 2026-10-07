#if DEBUG
    import Foundation
    import SwiftData

    /// 仅显式隔离测试注入一次读/写失败；生产运行与Release始终走真实名字服务。
    @MainActor
    enum UITestFamilyProfileEditorFactory {
        static let readFailureArgument = "--habito-ui-profile-read-fail-once"
        static let saveFailureArgument = "--habito-ui-profile-save-fail-once"

        static func make(context: ModelContext, arguments: [String]) -> FamilyProfileEditorViewModel {
            let enabled = arguments.contains(UITestLaunchConfiguration.enableArgument)
            var shouldFailRead = enabled && arguments.contains(readFailureArgument)
            var shouldFailSave = enabled && arguments.contains(saveFailureArgument)
            let service = FamilyProfileService(
                context: context,
                saveChanges: { context in
                    if shouldFailSave {
                        shouldFailSave = false
                        throw NSError(domain: "HabitoSyntheticUIProfileSave", code: 1)
                    }
                    try context.save()
                })
            return FamilyProfileEditorViewModel(
                loadNames: {
                    if shouldFailRead {
                        shouldFailRead = false
                        throw NSError(domain: "HabitoSyntheticUIProfileRead", code: 1)
                    }
                    return try service.load()
                }, saveNames: service.save)
        }
    }
#endif
