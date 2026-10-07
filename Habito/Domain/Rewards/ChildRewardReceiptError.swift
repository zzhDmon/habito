import Foundation

/// 展示生命周期错误与奖励结算错误分开，调用方不能用“补发”修复收据失败。
nonisolated enum ChildRewardReceiptError: Error, Equatable {
    case completionNotFound(UUID)
    case unavailableReceipt(UUID)
    case invalidDeliveryMetadata(UUID)
    case acknowledgementBeforeSettlement(UUID)
}
