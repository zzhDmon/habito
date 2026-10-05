import SwiftUI

/// 大辅助字号下标签和值上下排列，长日期不与标签争抢宽度；普通字号沿用系统样式。
struct ParentReviewSnapshotFieldStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: HabitoDesign.Spacing.xSmall) {
                configuration.label
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                configuration.content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent {
                configuration.content
            } label: {
                configuration.label
            }
            .labeledContentStyle(.automatic)
        }
    }
}
