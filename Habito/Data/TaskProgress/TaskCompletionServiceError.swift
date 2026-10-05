import Foundation

/// 完成结算无法安全进行时的明确边界，不允许 UI 先宣称已完成或已到账。
nonisolated enum TaskCompletionServiceError: Error, Equatable, Sendable {
    case modelNotInContext
    case invalidConfiguration(UUID)
    case requiresParentApproval(UUID)
    case invalidStoredCompletion(UUID)
    case invalidDuration(UUID)
    case submissionTimeMismatch(UUID)
    case legacyUndoCannotDeleteSettlement(UUID)
}
