/// 用户可纠正的失败与存储错误分开显示，避免让孩子因未知原因反复点击购买。
nonisolated enum PetFeedingFailure: Equatable, Sendable {
    case insufficientCoins
    case clockReversed
    case saveFailed
    case unavailable
}
