import Foundation
import SwiftUI
import Testing
@testable import Habito

@Suite("真实收据强反馈分层")
struct TaskSessionFeedbackPresentationTests {
    private let eventID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    private let eventDate = Date(timeIntervalSince1970: 1_000)

    @Test("完成收据按真实时机分层，零奖励也保持完成肯定", arguments: CompletionTiming.allCases, [false, true])
    func completionToneUsesReceipt(timing: CompletionTiming, zero: Bool) {
        let receipt = TaskCompletionResult(
            completionID: eventID, completedAt: eventDate, timing: timing,
            xp: zero ? 0 : 11, coins: zero ? 0 : 10, didComplete: true)
        let presentation = TaskSessionFeedbackPresentation(feedback: .completed(receipt))
        #expect(presentation.id == eventID)
        #expect(presentation.tone == (timing == .beforeReminder ? .autonomous : .completed))
        #expect(presentation.xp == (zero ? nil : 11))
        #expect(presentation.coins == (zero ? nil : 10))
        #expect(presentation.hasReward == !zero)
    }

    @Test("提交只肯定交付，不把提前提交显示成完成或到账", arguments: CompletionTiming.allCases)
    func submissionDoesNotInventCompletion(timing: CompletionTiming) {
        let receipt = TaskSubmissionResult(
            submissionID: eventID, submittedAt: eventDate, timing: timing,
            activeDurationSeconds: 120, didSubmit: true)
        let presentation = TaskSessionFeedbackPresentation(feedback: .submitted(receipt))
        #expect(presentation.id == eventID && presentation.tone == .submitted)
        #expect(presentation.xp == nil && presentation.coins == nil && !presentation.hasReward)
    }

    @Test("只展示正金额并完整保留整数边界，不重新合计或回算奖励", arguments: [0, 11, Int.max], [0, 7, Int.max])
    func amountsStayExactlyAsSaved(xp: Int, coins: Int) {
        let receipt = TaskCompletionResult(
            completionID: eventID, completedAt: eventDate, timing: .afterReminder,
            xp: xp, coins: coins, didComplete: true)
        let presentation = TaskSessionFeedbackPresentation(feedback: .completed(receipt))
        #expect(presentation.xp == (xp > 0 ? xp : nil))
        #expect(presentation.coins == (coins > 0 ? coins : nil))
        #expect(presentation.hasReward == (xp > 0 || coins > 0))
    }

    @Test("同一收据重复投影保持事件身份，不构造新的庆祝事件")
    func projectionKeepsStableIdentity() {
        let feedback = TaskSessionCompletionFeedback.completed(
            TaskCompletionResult(
                completionID: eventID, completedAt: eventDate, timing: .beforeReminder,
                xp: 11, coins: 10, didComplete: true))
        #expect(
            TaskSessionFeedbackPresentation(feedback: feedback) == TaskSessionFeedbackPresentation(feedback: feedback))
    }

    @Test("减少动态效果在出现前后都展示完整静态结果", arguments: [false, true])
    func reducedMotionNeverMovesOrHidesContent(revealed: Bool) {
        let motion = TaskSessionFeedbackMotion(reduceMotion: true, hasRevealed: revealed)
        #expect(motion.scale == 1 && motion.opacity == 1 && !motion.animatesReveal)
    }

    @Test("普通入场结束后回到完整结果，视觉策略不拥有延迟或业务事件", arguments: [false, true])
    func regularMotionEndsAtCompletePresentation(revealed: Bool) {
        let motion = TaskSessionFeedbackMotion(reduceMotion: false, hasRevealed: revealed)
        #expect(motion.animatesReveal)
        #expect(motion.scale == (revealed ? 1 : Double(HabitoDesign.Feedback.initialScale)))
        #expect(motion.opacity == (revealed ? 1 : HabitoDesign.Feedback.initialOpacity))
    }

    @Test("静态策略在最大字号仍可原生渲染普通、自主和等待卡", arguments: [TaskSessionFeedbackTone.completed, .autonomous, .submitted])
    @MainActor
    func reducedMotionCardRendersWithoutStartingAnimation(tone: TaskSessionFeedbackTone) throws {
        let feedback: TaskSessionCompletionFeedback
        if tone == .submitted {
            feedback = .submitted(
                TaskSubmissionResult(
                    submissionID: eventID, submittedAt: eventDate, timing: .beforeReminder,
                    activeDurationSeconds: 120, didSubmit: true))
        } else {
            feedback = .completed(
                TaskCompletionResult(
                    completionID: eventID, completedAt: eventDate,
                    timing: tone == .autonomous ? .beforeReminder : .afterReminder,
                    xp: 11, coins: 10, didComplete: true))
        }
        // ImageRenderer 直接渲染第一帧，不等待 .task 入场；显式策略不是系统开关实测。
        let renderer = ImageRenderer(
            content: TaskSessionFeedbackCard(
                presentation: TaskSessionFeedbackPresentation(feedback: feedback), reduceMotion: true, onDismiss: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 1_024)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 1_024 && image.height > 0)
    }
}
