import Foundation

/// 今日页成功加载后可直接渲染的展示值。
struct TodayScreenContent: Equatable, Sendable {
    let recommendedTask: KidTaskNavigationItem?
    let remainingTasks: [KidTaskNavigationItem]
    let completedCount: Int
    let totalCount: Int
    let isAllCompleted: Bool

    var isEmpty: Bool {
        recommendedTask == nil && remainingTasks.isEmpty
    }
}

extension TodayScreenContent {
    static let preview = TodayScreenContent(
        recommendedTask: .previewReading,
        remainingTasks: [.previewWriting, .previewCompleted],
        completedCount: 1,
        totalCount: 3,
        isAllCompleted: false
    )

    static let previewCarryOver = TodayScreenContent(
        recommendedTask: KidTaskNavigationItem(
            id: UUID(),
            title: String(localized: "kidTask.previewTitle"),
            iconName: "book.fill",
            scheduledTimeText: String(localized: "kidTask.previewTime"),
            targetDurationText: String(localized: "kidTask.previewDuration"),
            status: .inProgress,
            statusText: String(localized: "kidTask.statusCarryOver"),
            statusIconName: "clock.arrow.circlepath"
        ),
        remainingTasks: [],
        completedCount: 0,
        totalCount: 0,
        isAllCompleted: false
    )
}
