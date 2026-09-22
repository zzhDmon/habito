import Foundation

/// 会改变计时会话状态的领域动作。
nonisolated enum TimerSessionAction: String, CaseIterable, Sendable {
    case pause
    case resume
    case end
}
