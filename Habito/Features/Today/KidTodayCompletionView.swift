import SwiftUI

/// 当天收尾的静态完成仪式，与单次到账反馈分开，不因页面重新出现而播放或发奖。
struct KidTodayCompletionView: View {
    let summary: TodayCompletionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.large) {
            DogCharacter(celebrating: true)
            Text("kidToday.dailyCompletionStamp")
                .font(.title2.weight(.heavy))
                .padding(HabitoDesign.Spacing.small)
                .modifier(MangaPanel(fill: HabitoDesign.Manga.panel))
                .foregroundStyle(HabitoDesign.Manga.successInk)
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
                .foregroundStyle(HabitoDesign.Manga.secondaryInk)
                .accessibilityIdentifier(HabitoAccessibilityID.todayCompletionRest)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .foregroundStyle(HabitoDesign.Manga.ink)
        .modifier(MangaPanel(fill: HabitoDesign.Manga.successPaper, emphasized: true))
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
