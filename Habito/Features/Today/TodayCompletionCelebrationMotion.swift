/// 只控制装饰印章的视觉策略，正文、真实数量和按钮不缩放或隐藏。
///
/// - Important: 不含时间、延迟或业务回调；减少动态效果从第一帧就是完整静态印章。
nonisolated struct TodayCompletionCelebrationMotion: Equatable, Sendable {
    let emblemScale: Double
    let animatesReveal: Bool

    init(reduceMotion: Bool, hasRevealed: Bool) {
        emblemScale = reduceMotion || hasRevealed ? 1 : HabitoDesign.Feedback.initialScale
        animatesReveal = !reduceMotion
    }
}
