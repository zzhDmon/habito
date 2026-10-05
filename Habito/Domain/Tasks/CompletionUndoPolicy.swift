import Foundation

/// 沿用孩子入口的五秒撤销窗口；领域与 UI 共用，页面重建不能延长窗口。
nonisolated enum CompletionUndoPolicy {
    static let window: TimeInterval = 5

    static func canUndo(completedAt: Date, now: Date) -> Bool {
        completedAt.timeIntervalSinceReferenceDate.isFinite && now.timeIntervalSinceReferenceDate.isFinite
            && now >= completedAt && now < completedAt.addingTimeInterval(window)
    }
}
