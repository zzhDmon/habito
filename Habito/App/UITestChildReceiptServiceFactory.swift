#if DEBUG
    import Foundation
    import SwiftData

    /// 确认失败仅注入显式隔离 UI 测试，不改变普通 Debug/Release 的保存行为。
    @MainActor
    enum UITestChildReceiptServiceFactory {
        static let failureArgument = "--habito-ui-receipt-save-fail"

        static func make(context: ModelContext, arguments: [String]) -> ChildRewardReceiptService {
            guard arguments.contains(UITestLaunchConfiguration.enableArgument), arguments.contains(failureArgument)
            else { return ChildRewardReceiptService(context: context) }
            return ChildRewardReceiptService(
                context: context,
                saveChanges: { _ in throw NSError(domain: "HabitoSyntheticUIReceiptSave", code: 1) })
        }
    }
#endif
