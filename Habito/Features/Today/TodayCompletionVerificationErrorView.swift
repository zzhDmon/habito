import SwiftUI

/// 额外仪式无法校验时的独立提示，不把已经保存的打卡或奖励改称失败。
struct TodayCompletionVerificationErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Label("kidToday.celebrationVerificationErrorTitle", systemImage: "exclamationmark.circle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("kidToday.celebrationVerificationErrorDescription").font(.body)
            Button(action: onRetry) {
                Label("kidToday.retry", systemImage: "arrow.clockwise")
                    .frame(minWidth: HabitoDesign.Layout.minimumTapSize, minHeight: HabitoDesign.Layout.minimumTapSize)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier(HabitoAccessibilityID.todayCelebrationRetry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .background(.background, in: .rect(cornerRadius: HabitoDesign.CornerRadius.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.todayCelebrationError)
    }
}

#Preview("仪式校验失败 · 横屏") {
    TodayCompletionVerificationErrorView(onRetry: {}).padding().frame(width: 900)
}

#Preview("仪式校验失败 · 最大字号") {
    TodayCompletionVerificationErrorView(onRetry: {})
        .padding().frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility5)
}
