/// 纯视觉策略，用固定布尔值验证减少动态效果从第一帧起不缩放、不隐藏信息。
///
/// 正式布尔输入由 SwiftUI 的只读系统环境提供；策略没有时钟、延迟或业务回调。
nonisolated struct TaskSessionFeedbackMotion: Equatable, Sendable {
    let scale: Double
    let opacity: Double
    let animatesReveal: Bool

    init(reduceMotion: Bool, hasRevealed: Bool) {
        scale = reduceMotion || hasRevealed ? 1 : Double(HabitoDesign.Feedback.initialScale)
        opacity = reduceMotion || hasRevealed ? 1 : HabitoDesign.Feedback.initialOpacity
        animatesReveal = !reduceMotion
    }
}
