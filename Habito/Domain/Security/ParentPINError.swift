/// 创建家长 PIN 时可能出现的格式错误。
nonisolated enum ParentPINError: Error, Equatable, Sendable {
    case invalidFormat
}
