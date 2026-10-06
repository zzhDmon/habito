/// 展示强度只区分真实结果，不包含奖励数值或任何结算规则。
nonisolated enum TaskSessionFeedbackTone: Equatable, Sendable {
    case submitted
    case completed
    case autonomous
}
