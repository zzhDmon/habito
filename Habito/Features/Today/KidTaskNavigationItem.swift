import Foundation

/// 孩子页面导航所需的最小只读任务值。
///
/// 它刻意不持有 SwiftData 模型，避免页面导航期间绑定可变持久化对象。
/// M2-002 会由查询结果生成该值。
struct KidTaskNavigationItem: Hashable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let iconName: String
    let scheduledTimeText: String
    let targetDurationText: String
}

extension KidTaskNavigationItem {
    /// 只供 Preview 使用，不会写入正式数据容器。
    static let previewReading = KidTaskNavigationItem(
        id: UUID(),
        title: String(localized: "kidTask.previewTitle"),
        iconName: "book.fill",
        scheduledTimeText: String(localized: "kidTask.previewTime"),
        targetDurationText: String(localized: "kidTask.previewDuration")
    )
}
