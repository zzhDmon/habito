import SwiftUI

/// 已保存收据的单次礼花装饰。触发值来自收据局部生命周期，不驱动奖励、保存或撤销计时。
///
/// 原生关键帧在 1.4 秒后停止，不创建常驻计时器；减少动态效果时直接呈现静态星光。
struct CompletionConfettiView: View {
    let hasRevealed: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            if reduceMotion {
                HStack {
                    Image(systemName: "sparkles")
                    Spacer()
                    Image(systemName: "sparkles")
                }
                .font(.title2)
                .foregroundStyle(HabitoDesign.Manga.action)
                .padding(HabitoDesign.Spacing.medium)
            } else {
                ForEach(0..<HabitoDesign.Feedback.confettiCount, id: \.self) { index in
                    let lift = 0.2 + Double(index % 5) * 0.1
                    let fall = 0.2 + Double((index * 7) % 11) * 0.03
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index.isMultiple(of: 2) ? HabitoDesign.Manga.action : HabitoDesign.Manga.successInk)
                        .frame(width: index.isMultiple(of: 3) ? 9 : 6, height: 12)
                        .keyframeAnimator(initialValue: 1.0, trigger: hasRevealed) { content, progress in
                            // 固定轨迹避免重绘时随机跳动；左右散开、向上抛起后落下并消失。
                            content
                                .rotationEffect(.degrees(Double(index * 37) + progress * 240))
                                .position(
                                    x: size.width / 2
                                        + CGFloat(progress) * size.width
                                        * (Double(index) / Double(HabitoDesign.Feedback.confettiCount - 1) - 0.5),
                                    y: size.height * (0.6 - sin(progress * .pi) * lift + progress * fall)
                                )
                                .opacity(hasRevealed ? max(0, min(1, (1 - progress) * 2)) : 0)
                        } keyframes: { _ in
                            // 默认停在透明终帧，避免系统动态设置切换后残留一团静止纸屑。
                            MoveKeyframe(0)
                            LinearKeyframe(1, duration: HabitoDesign.Feedback.confettiDuration)
                        }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("礼花 · 静态降级") {
    CompletionConfettiView(hasRevealed: true, reduceMotion: true)
        .frame(width: 500, height: HabitoDesign.Feedback.confettiHeight)
        .background(HabitoDesign.Manga.paper)
}
