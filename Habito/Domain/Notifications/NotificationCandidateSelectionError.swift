import Foundation

/// 通知候选输入无法形成确定且诚实的覆盖结果。
nonisolated enum NotificationCandidateSelectionError: Error, Equatable {
    case invalidPrimaryLimit(Int)
    case duplicateOccurrenceID(UUID)
    case candidateBeyondAvailableHorizon(UUID)
}
