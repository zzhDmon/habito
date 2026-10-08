#if DEBUG
    import Foundation
    import SwiftData

    /// 只在显式隔离UI测试中模拟一次读取失败，重试回到真实服务；正式数据不走失败注入。
    @MainActor
    enum UITestPetProfileFactory {
        static let readFailureArgument = "--habito-ui-pet-read-fail-once"

        static func make(context: ModelContext, arguments: [String]) -> PetProfileViewModel {
            var shouldFail =
                arguments.contains(UITestLaunchConfiguration.enableArgument)
                && arguments.contains(readFailureArgument)
            let service = FamilyProfileService(context: context)
            return PetProfileViewModel(loadNames: {
                if shouldFail {
                    shouldFail = false
                    throw CocoaError(.fileReadUnknown)
                }
                return try service.load()
            })
        }
    }
#endif
