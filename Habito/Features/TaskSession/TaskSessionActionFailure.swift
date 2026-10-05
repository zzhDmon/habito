import Foundation

/// 操作失败不覆盖已加载事实；币不足与未保存必须给孩子不同提示。
enum TaskSessionActionFailure: Equatable, Sendable {
    case insufficientCoins
    case saveFailed
    case unavailable

    var messageKey: String {
        switch self {
        case .insufficientCoins: "taskSession.undoInsufficientCoins"
        case .saveFailed: "taskSession.actionSaveFailed"
        case .unavailable: "taskSession.actionUnavailable"
        }
    }
}
