import Foundation

/// 完成记录的创建来源，用于区分孩子打卡与家长更正。
nonisolated enum CompletionSource: String, CaseIterable, Sendable {
    case childManual
    case parentCorrection
}
