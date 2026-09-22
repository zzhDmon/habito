import Foundation

/// V0 支持的重复规则种类。
nonisolated enum TaskRecurrenceKind: String, CaseIterable, Sendable {
    case once
    case weekly
}
