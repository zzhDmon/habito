import SwiftUI

/// 一次真实今日通关的轻量仪式；不弹模态、不发奖，也不阻塞孩子继续。
///
/// View只转交稳定ID。共享状态授予一次动画资格，局部State仅描述装饰的视觉帧，不能负责业务去重。
/// - Note: 正式宿主读取系统只读Reduce Motion环境后传入；Preview/单测的固定输入不代表系统开关现场验收。
struct TodayCompletionCelebrationView: View {
    let event: TodayCompletionCelebrationEvent
    let reduceMotion: Bool
    let onClaimAnimation: (UUID) -> Bool
    let onContinue: (UUID) -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = HabitoDesign.Feedback.symbolSize
    @State private var hasRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: symbolSize))
                .foregroundStyle(HabitoDesign.Feedback.completed)
                .padding(HabitoDesign.Feedback.symbolPadding)
                .background(
                    HabitoDesign.Feedback.completed.opacity(HabitoDesign.Feedback.badgeTintOpacity), in: Circle()
                )
                .scaleEffect(motion.emblemScale)
                .accessibilityHidden(true)
            Text("kidToday.dailyCompletionStamp")
                .font(.title2.bold())
                .accessibilityIdentifier(HabitoAccessibilityID.todayCompletionStamp)
            Text("kidToday.dailyCelebrationTitle")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(HabitoAccessibilityID.todayCelebrationTitle)
            Text("kidToday.dailyCelebrationDescription").font(.title3)
            Text("kidToday.dailyCompletionCount \(event.completedCount)")
                .font(.title2.bold())
                .accessibilityIdentifier(HabitoAccessibilityID.todayCompletionCount)
            Text("kidToday.dailyCompletionRest")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HabitoAccessibilityID.todayCompletionRest)
            Button(action: continueAfterCelebration) {
                Label("kidToday.dailyCelebrationContinue", systemImage: "checkmark.circle")
                    .frame(minWidth: HabitoDesign.Layout.minimumTapSize, minHeight: HabitoDesign.Layout.minimumTapSize)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier(HabitoAccessibilityID.todayCelebrationContinue)
            .accessibilityHint("kidToday.dailyCelebrationContinueHint")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(
            HabitoDesign.Feedback.completed.opacity(HabitoDesign.Feedback.cardTintOpacity),
            in: .rect(cornerRadius: HabitoDesign.CornerRadius.card)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.todayCompletion)
        .task(id: event.id) { revealEmblem() }
    }

    private var motion: TodayCompletionCelebrationMotion {
        TodayCompletionCelebrationMotion(reduceMotion: reduceMotion, hasRevealed: hasRevealed)
    }

    /// 没有新资格的View重建直接进入静态终帧；动作不等待动画，也不读取存储。
    private func revealEmblem() {
        let didClaim = onClaimAnimation(event.id)
        if didClaim && motion.animatesReveal {
            withAnimation(HabitoDesign.Feedback.reveal) { hasRevealed = true }
        } else {
            // 静态路径明确禁止继承导航容器的动画；旧事件或减少动态不能借页面转场重新弹出。
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { hasRevealed = true }
        }
    }

    private func continueAfterCelebration() {
        onContinue(event.id)
    }
}

#Preview("新通关 · 横屏") {
    if let event = TodayCompletionCelebrationPreview.event {
        TodayCompletionCelebrationView(
            event: event, reduceMotion: false, onClaimAnimation: { _ in true }, onContinue: { _ in }
        )
        .padding().frame(width: 900)
    }
}

#Preview("新通关 · 最大字号窄宽") {
    if let event = TodayCompletionCelebrationPreview.event {
        TodayCompletionCelebrationView(
            event: event, reduceMotion: false, onClaimAnimation: { _ in true }, onContinue: { _ in }
        )
        .padding().frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility5)
    }
}

#Preview("新通关 · 减少动态深色") {
    if let event = TodayCompletionCelebrationPreview.event {
        TodayCompletionCelebrationView(
            event: event, reduceMotion: true, onClaimAnimation: { _ in false }, onContinue: { _ in }
        )
        .padding().frame(width: 900)
        .preferredColorScheme(.dark)
    }
}
