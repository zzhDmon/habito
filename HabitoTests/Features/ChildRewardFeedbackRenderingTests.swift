import SwiftUI
import Testing
@testable import Habito

@MainActor
struct ChildRewardFeedbackRenderingTests {
    @Test(
        "普通/自主/零奖励与确认错误在普通和最大字号原生渲染",
        arguments: [CompletionTiming.beforeReminder, .afterReminder],
        [(false, false), (false, true), (true, false), (true, true)])
    func receiptRendersAtBothTextSizes(timing: CompletionTiming, options: (Bool, Bool)) throws {
        let (zero, large) = options
        let receipt = ChildRewardReceipt(
            completionID: UUID(), occurrenceID: UUID(), title: "固定合成审核收据",
            completedAt: .distantPast, settledAt: .distantPast, timing: timing,
            xp: zero ? 0 : 11, coins: zero ? 0 : (timing == .beforeReminder ? 10 : 7))
        let renderer = ImageRenderer(
            content: ChildRewardFeedbackView(
                state: .receipt(receipt), acknowledgementFailed: true,
                onContinue: { _ in }, onRetry: {}
            )
            .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
            .frame(width: 320)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height > 0)
    }

    @Test("加载错误可渲染独立重试，不能冒充空态", arguments: [false, true])
    func loadFailureRendersRetry(large: Bool) throws {
        let renderer = ImageRenderer(
            content: ChildRewardFeedbackView(
                state: .failed, acknowledgementFailed: false, onContinue: { _ in }, onRetry: {}
            )
            .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
            .frame(width: 320)
        )
        renderer.scale = 1
        #expect(try #require(renderer.cgImage).height > 0)
    }
}
