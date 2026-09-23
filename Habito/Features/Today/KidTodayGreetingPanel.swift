import SwiftUI

/// 今日页左侧的问候和模式说明。
struct KidTodayGreetingPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Image(systemName: "sun.max.fill")
                .font(.largeTitle)
                .foregroundStyle(HabitoDesign.Palette.attention)
                .accessibilityHidden(true)

            Text("kidToday.greeting")
                .font(.largeTitle)
                .bold()

            Text("kidToday.subtitle")
                .font(.title3)
                .foregroundStyle(.secondary)

            Label("kidToday.childMode", systemImage: "figure.child")
                .font(.headline)
                .padding(.horizontal, HabitoDesign.Spacing.medium)
                .padding(.vertical, HabitoDesign.Spacing.small)
                .background(.quaternary, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
    }
}
