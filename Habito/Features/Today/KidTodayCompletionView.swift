import SwiftUI

/// 当天收尾的静态完成仪式，与单次到账反馈分开，不因页面重新出现而播放或发奖。
struct KidTodayCompletionView: View {
    let summary: TodayCompletionSummary
    // 系统字号只放大装饰印章；正文使用语义字体、自然换行，没有固定高度或缩字。
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = HabitoDesign.Feedback.symbolSize

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: symbolSize))
                .foregroundStyle(HabitoDesign.Feedback.completed)
                .padding(HabitoDesign.Feedback.symbolPadding)
                .background(
                    HabitoDesign.Feedback.completed.opacity(HabitoDesign.Feedback.badgeTintOpacity), in: Circle()
                )
                .accessibilityHidden(true)
            Text("kidToday.dailyCompletionStamp")
                .font(.title2.bold())
                // 系统绿色适合装饰，不用低对比的绿色文字叠在浅绿色背景上。
                .foregroundStyle(.primary)
                .accessibilityIdentifier(HabitoAccessibilityID.todayCompletionStamp)
            Text("kidToday.completedTitle")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("kidToday.completedDescription")
                .font(.title3)
            Text("kidToday.dailyCompletionCount \(summary.completedCount)")
                .font(.title2.bold())
                .accessibilityIdentifier(HabitoAccessibilityID.todayCompletionCount)
            Text("kidToday.dailyCompletionRest")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HabitoAccessibilityID.todayCompletionRest)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(
            HabitoDesign.Feedback.completed.opacity(HabitoDesign.Feedback.cardTintOpacity),
            in: .rect(cornerRadius: HabitoDesign.CornerRadius.card)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.todayCompletion)
    }
}

#Preview("今日通关 · 横屏") {
    if let summary = TodayScreenContent.previewCompleted.dailyCompletion {
        KidTodayCompletionView(summary: summary).padding().frame(width: 900)
    }
}

#Preview("今日通关 · 最大字号窄宽") {
    if let summary = TodayScreenContent.previewCompleted.dailyCompletion {
        KidTodayCompletionView(summary: summary)
            .padding().frame(width: 320)
            .environment(\.dynamicTypeSize, .accessibility5)
    }
}
