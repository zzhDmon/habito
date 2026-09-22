import Foundation

/// 领域对象收到当前状态不允许的动作。
///
/// 该错误保留稳定的英文状态和动作值，便于日志与测试定位；面向用户的中文提示
/// 应由 Feature 层根据具体操作提供，不直接展示 `description`。
nonisolated struct DomainStateTransitionError: Error, Equatable, Sendable, CustomStringConvertible {
    let state: String
    let action: String

    var description: String {
        "Action '\(action)' is not allowed while state is '\(state)'."
    }
}
