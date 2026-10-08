import SwiftUI

/// 审核条目把快照与动作分组；金额为通过后的预期，不能当作现在已到账。
struct ParentReviewQueueRow: View {
    let item: ParentReviewQueueItem
    let onApprove: () -> Void
    let onReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.medium) {
            Label {
                Text(item.title)
            } icon: {
                TaskIcon(storedName: item.iconName)
            }
            .font(.title2.bold())
            ParentReviewSnapshotView(item: item)
            Button("parentReview.approve", systemImage: "checkmark.circle", action: onApprove)
                .buttonStyle(MangaButtonStyle())
                .controlSize(.large)
                .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentReviewApprove(item.id))
            Button("parentReview.return", systemImage: "arrow.uturn.backward", action: onReturn)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: HabitoDesign.Layout.minimumTapSize)
                .accessibilityIdentifier(HabitoAccessibilityID.parentReviewReturn(item.id))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HabitoDesign.Spacing.large)
        .foregroundStyle(HabitoDesign.Manga.ink)
        .modifier(MangaPanel())
        // 独立容器避免 identifier 继承覆盖内部按钮；不能合并审核动作成一个读屏元素。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HabitoAccessibilityID.parentReviewItem(item.id))
    }
}

#Preview("审核条目 · 大字") {
    ScrollView {
        ParentReviewQueueRow(item: ParentReviewPreview.item, onApprove: {}, onReturn: {})
            .padding()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
