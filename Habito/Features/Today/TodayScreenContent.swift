import Foundation

/// 今日页成功加载后可直接渲染的展示值。
struct TodayScreenContent: Equatable, Sendable {
    let recommendedTask: KidTaskNavigationItem?
    let remainingTasks: [KidTaskNavigationItem]
    let remainingTaskGroups: [TodayTaskGroup]
    let completedCount: Int
    let totalCount: Int
    let isAllCompleted: Bool
    let dailyCompletion: TodayCompletionSummary?
    let emptyReason: TodayEmptyReason

    /// 在页面状态创建时投影一次，避免 View.body 内重复编排任务或维护另一份可变分组。
    init(
        recommendedTask: KidTaskNavigationItem?, remainingTasks: [KidTaskNavigationItem],
        completedCount: Int, totalCount: Int, isAllCompleted: Bool, emptyReason: TodayEmptyReason = .restDay
    ) {
        self.recommendedTask = recommendedTask
        self.remainingTasks = remainingTasks
        remainingTaskGroups = TodayTaskGroup.makeGroups(from: remainingTasks)
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.isAllCompleted = isAllCompleted
        self.emptyReason = emptyReason
        dailyCompletion = TodayCompletionSummary(
            completedCount: completedCount, totalCount: totalCount, isAllCompleted: isAllCompleted)
    }

    var isEmpty: Bool {
        recommendedTask == nil && remainingTasks.isEmpty
    }
}

extension TodayScreenContent {
    static let previewCompleted = TodayScreenContent(
        recommendedTask: nil, remainingTasks: [.previewCompleted],
        completedCount: 1, totalCount: 1, isAllCompleted: true)

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
            statusIconName: "clock.arrow.circlepath",
            isCarryOver: true
        ),
        remainingTasks: [],
        completedCount: 0,
        totalCount: 0,
        isAllCompleted: false
    )
}
