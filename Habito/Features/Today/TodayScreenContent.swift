/// 今日页成功加载后可直接渲染的展示值。
struct TodayScreenContent: Equatable, Sendable {
    let recommendedTask: KidTaskNavigationItem?
    let remainingTasks: [KidTaskNavigationItem]
    let completedCount: Int
    let totalCount: Int
    let isAllCompleted: Bool
}

extension TodayScreenContent {
    static let preview = TodayScreenContent(
        recommendedTask: .previewReading,
        remainingTasks: [.previewWriting, .previewCompleted],
        completedCount: 1,
        totalCount: 3,
        isAllCompleted: false
    )
}
