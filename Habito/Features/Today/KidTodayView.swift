import SwiftUI

/// 孩子打开 App 后看到的今日页基础结构。
struct KidTodayView: View {
    let state: TodayViewState
    let rewardState: TodayRewardState
    let makeTimingPresentation: @MainActor (KidTaskNavigationItem) -> KidTaskTimingPresentation
    let onSelectTask: (KidTaskNavigationItem) -> Void
    let onRetry: () -> Void
    let onRetryRewards: () -> Void
    var feedbackState: ChildRewardFeedbackState = .idle
    var acknowledgementFailed = false
    var onContinueReceipt: (UUID) -> Void = { _ in }
    var onRetryReceipt: () -> Void = {}
    var celebrationEvent: TodayCompletionCelebrationEvent?
    var celebrationVerificationFailed = false
    var onClaimCelebration: (UUID) -> Bool = { _ in false }
    var onContinueCelebration: (UUID) -> Void = { _ in }
    var onRetryCelebration: () -> Void = {}

    var body: some View {
        AdaptiveTwoColumnLayout {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
                ChildRewardFeedbackView(
                    state: feedbackState, acknowledgementFailed: acknowledgementFailed,
                    onContinue: onContinueReceipt, onRetry: onRetryReceipt)
                KidTodayGreetingPanel()
                KidTodayRewardOverview(state: rewardState, onRetry: onRetryRewards)
                if case let .loaded(content) = state, content.totalCount > 0 {
                    KidTodayProgressView(
                        completedCount: content.completedCount, totalCount: content.totalCount)
                }
            }
        } trailing: {
            KidTodayTaskContent(
                state: state, makeTimingPresentation: makeTimingPresentation,
                onSelectTask: onSelectTask, onRetry: onRetry,
                celebrationEvent: celebrationEvent,
                celebrationVerificationFailed: celebrationVerificationFailed,
                onClaimCelebration: onClaimCelebration, onContinueCelebration: onContinueCelebration,
                onRetryCelebration: onRetryCelebration)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(HabitoAccessibilityID.todayScreen)
        .navigationTitle("kidToday.navigationTitle")
        .foregroundStyle(HabitoDesign.Manga.ink)
        .tint(HabitoDesign.Manga.successInk)
        .background(HabitoDesign.Manga.paper)
    }
}

#Preview("今日 · iPad 横屏") {
    NavigationStack {
        KidTodayView(
            state: .loaded(.preview), rewardState: .loaded(RewardBalance(effectiveXP: 11, coins: 7)),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }, onRetry: {},
            onRetryRewards: {})
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 空态") {
    NavigationStack {
        KidTodayView(
            state: .loaded(
                TodayScreenContent(
                    recommendedTask: nil,
                    remainingTasks: [],
                    completedCount: 0,
                    totalCount: 0,
                    isAllCompleted: false
                )
            ),
            rewardState: .loaded(RewardBalance(effectiveXP: 11, coins: 7)),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in },
            onRetry: {}, onRetryRewards: {}
        )
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 全部完成") {
    NavigationStack {
        KidTodayView(
            state: .loaded(
                TodayScreenContent(
                    recommendedTask: nil,
                    remainingTasks: [.previewCompleted],
                    completedCount: 1,
                    totalCount: 1,
                    isAllCompleted: true
                )
            ),
            rewardState: .loaded(RewardBalance(effectiveXP: 11, coins: 7)),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in },
            onRetry: {}, onRetryRewards: {}
        )
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 跨日任务进行中") {
    NavigationStack {
        KidTodayView(
            state: .loaded(.previewCarryOver),
            rewardState: .loaded(RewardBalance(effectiveXP: 11, coins: 7)),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in },
            onRetry: {}, onRetryRewards: {}
        )
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 数据错误") {
    NavigationStack {
        KidTodayView(
            state: .failed, rewardState: .loaded(RewardBalance(effectiveXP: 11, coins: 7)),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in },
            onRetry: {}, onRetryRewards: {})
    }
    .frame(width: 1_194, height: 834)
}

#Preview("今日 · 辅助功能字号") {
    NavigationStack {
        KidTodayView(
            state: .loaded(.preview), rewardState: .loaded(RewardBalance(effectiveXP: 11, coins: 7)),
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }, onRetry: {},
            onRetryRewards: {})
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("今日 · 资产错误仍可查看任务") {
    NavigationStack {
        KidTodayView(
            state: .loaded(.preview), rewardState: .failed,
            makeTimingPresentation: KidTaskTimingPresentation.preview, onSelectTask: { _ in }, onRetry: {},
            onRetryRewards: {})
    }
    .frame(width: 1_194, height: 834)
    .environment(\.dynamicTypeSize, .accessibility5)
}
