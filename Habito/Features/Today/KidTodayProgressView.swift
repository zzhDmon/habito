import SwiftUI

/// 今日完成数和总数的文字、图标与进度条组合。
struct KidTodayProgressView: View {
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            Label("kidToday.progressTitle", systemImage: "chart.bar.fill")
                .font(.headline)
            Text(
                String.localizedStringWithFormat(
                    String(localized: "kidToday.progressFormat"),
                    completedCount,
                    totalCount
                )
            )
            .font(.title2)
            .bold()

            ProgressView(value: Double(completedCount), total: Double(max(totalCount, 1)))
                .tint(HabitoDesign.Palette.success)
                .accessibilityLabel("kidToday.progressTitle")
                .accessibilityValue("\(completedCount) / \(totalCount)")
        }
        .padding(HabitoDesign.Spacing.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HabitoDesign.CornerRadius.card))
    }
}
