import SwiftUI

/// 原提交的只读详情；日期键不转成“设备今天”，时间格式仅用于展示。
struct ParentReviewSnapshotView: View {
    let item: ParentReviewQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: HabitoDesign.Spacing.small) {
            LabeledContent("parentReview.taskDate", value: item.taskDate.dateKey)
            LabeledContent("parentReview.submittedAt") {
                Text(item.submittedAt, format: .dateTime.year().month().day().hour().minute())
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(HabitoAccessibilityID.parentReviewSubmittedAt)
            LabeledContent("parentReview.reminderAt") {
                Text(item.reminderAt, format: .dateTime.year().month().day().hour().minute())
            }
            LabeledContent("parentReview.duration") {
                // Measurement 直接格式化有限秒数，不把可能较大的累计值强转成 Int。
                Text(
                    Measurement(value: item.activeDurationSeconds, unit: UnitDuration.seconds),
                    format: .measurement(width: .wide, usage: .asProvided))
            }
            Label(
                timingKey,
                systemImage: item.timing == .beforeReminder ? "star.circle" : "clock"
            )
            .accessibilityLabel(timingKey)
            Text("parentReview.expectedDescription")
                .foregroundStyle(.secondary)
            LabeledContent("parentReview.expectedXP") { Text(item.expectedXP, format: .number) }
            LabeledContent("parentReview.expectedCoins") { Text(item.expectedCoins, format: .number) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(HabitoAccessibilityID.parentReviewExpectedCoins)
            if item.expectedAutonomyCoins > 0 {
                LabeledContent("parentReview.expectedAutonomyCoins") {
                    Text(item.expectedAutonomyCoins, format: .number)
                }
            }
        }
        .labeledContentStyle(ParentReviewSnapshotFieldStyle())
        .font(.body)
    }

    private var timingKey: LocalizedStringKey {
        item.timing == .beforeReminder ? "parentReview.autonomous" : "parentReview.afterReminder"
    }
}

#Preview("冻结快照") {
    ParentReviewSnapshotView(item: ParentReviewPreview.item).padding()
}
