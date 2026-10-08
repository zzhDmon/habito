import Foundation
import SwiftUI
import Testing
@testable import Habito

@MainActor
@Suite("升级反馈展示与降级失效")
struct PetGrowthFeedbackViewModelTests {
    @Test("首次不庆祝，真实跨级合并且刷新不替换，关闭后不重播")
    func baselineUpgradeRefreshAndDismiss() {
        var observation: PetGrowthObservation? = PetGrowthObservation(previousLevel: nil, currentLevel: 1)
        var reads = 0
        let model = PetGrowthFeedbackViewModel {
            reads += 1; return observation
        }
        #expect(reads == 0)
        model.refresh()
        #expect(model.event == nil)
        observation = PetGrowthObservation(previousLevel: 1, currentLevel: 3)
        model.refresh()
        #expect(model.event == observation)
        observation = PetGrowthObservation(previousLevel: 3, currentLevel: 4)
        model.refresh()
        #expect(model.event == PetGrowthObservation(previousLevel: 1, currentLevel: 4))
        observation = PetGrowthObservation(previousLevel: 4, currentLevel: 4)
        model.refresh()
        #expect(model.event?.previousLevel == 1)
        model.dismiss(); model.refresh()
        #expect(model.event == nil)
    }

    @Test("失败撤旧并可重试，真实降级撤下尚未关闭的升级")
    func failureAndDowngrade() {
        var fail = false
        var observation = PetGrowthObservation(previousLevel: 1, currentLevel: 2)
        let model = PetGrowthFeedbackViewModel {
            if fail { throw CocoaError(.fileWriteUnknown) }
            return observation
        }
        model.refresh(); fail = true; model.refresh()
        #expect(model.failed && model.event == nil)
        fail = false; model.refresh()
        #expect(!model.failed && model.event == observation)
        observation = PetGrowthObservation(previousLevel: 2, currentLevel: 1)
        model.refresh()
        #expect(model.event == nil)
    }

    @Test("升级与错误普通/MAX深色、减少动态均渲染", arguments: [false, true], [false, true])
    func reducedMotionRendering(failed: Bool, reduced: Bool) throws {
        let renderer = ImageRenderer(
            content: PetLevelFeedbackView(
                reduceMotion: reduced,
                event: PetGrowthObservation(previousLevel: 1, currentLevel: 3), failed: failed, onContinue: {},
                onRetry: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.colorScheme, .dark).frame(width: 375))
        #expect(try #require(renderer.cgImage).height > 0)
    }
}
