import SwiftUI
import Testing
@testable import Habito

@Suite("今日仪式组件首帧")
@MainActor
struct TodayCompletionCelebrationRenderingTests {
    @Test("装饰印章只有普通初帧可缩放，减少动态从首帧静态完整", arguments: [false, true], [false, true])
    func motionRespectsReduceMotionFromFirstFrame(reduceMotion: Bool, revealed: Bool) {
        let motion = TodayCompletionCelebrationMotion(reduceMotion: reduceMotion, hasRevealed: revealed)
        #expect(motion.emblemScale == (reduceMotion || revealed ? 1 : HabitoDesign.Feedback.initialScale))
        #expect(motion.animatesReveal == !reduceMotion)
    }

    @Test(
        "仪式在窄宽/横屏、普通/MAX及固定减少动态输入下原生渲染，浅深色均有完整首帧",
        arguments: [false, true], [(320.0, false), (320.0, true), (900.0, false), (900.0, true)])
    func celebrationRendersAtBothTextSizes(reduceMotion: Bool, options: (Double, Bool)) throws {
        let event = try #require(TodayCompletionCelebrationPreview.event)
        let (width, large) = options
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(
                content:
                    TodayCompletionCelebrationView(
                        event: event, reduceMotion: reduceMotion, onClaimAnimation: { _ in false }, onContinue: { _ in }
                    )
                    .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                    .environment(\.colorScheme, scheme)
                    .frame(width: width))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(width) && image.height > 0)
        }
    }

    @Test("仪式校验错误在窄宽/MAX和浅深色原生渲染，失败不冒充空态", arguments: [false, true])
    func verificationErrorRendersIndependentRetry(large: Bool) throws {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(
                content:
                    TodayCompletionVerificationErrorView(onRetry: {})
                    .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 320))
            renderer.scale = 1
            #expect(try #require(renderer.cgImage).height > 0)
        }
    }
}
