import Foundation

/// 完成记录来源；家长通过与手动更正分开，不用来源代替提交时间的自主判定。
nonisolated enum CompletionSource: String, CaseIterable, Sendable {
    case childManual
    case parentCorrection
    case parentApproval
}
