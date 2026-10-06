import SwiftUI
import Testing
@testable import Habito

@MainActor
@Suite("儿童资产概览原生渲染")
struct KidTodayRewardRenderingTests {
    @Test("零余额与整数边界在普通及最大字号均能原生渲染", arguments: [0, 11, Int.max], [false, true])
    func balanceRendersAtBothTextSizes(amount: Int, large: Bool) throws {
        let renderer = ImageRenderer(
            content: KidTodayRewardOverview(
                state: .loaded(RewardBalance(effectiveXP: amount, coins: amount)), onRetry: {}
            )
            .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
            .frame(width: 320)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 320 && image.height > 0)
    }

    @Test("读取失败仍可原生渲染重试区域，不以零余额占位", arguments: [false, true])
    func failureRendersIndependentRetry(large: Bool) throws {
        let renderer = ImageRenderer(
            content: KidTodayRewardOverview(state: .failed, onRetry: {})
                .environment(\.dynamicTypeSize, large ? .accessibility5 : .large)
                .frame(width: 320)
        )
        renderer.scale = 1
        #expect(try #require(renderer.cgImage).height > 0)
    }
}
