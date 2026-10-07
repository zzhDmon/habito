import Foundation

/// 已保存且经过审计的审核奖励收据；只传值，不把 SwiftData 活跃对象交给页面。
///
/// - Important: 收据没有发奖能力。提交时刻决定自主性，settledAt 则表示真实审核到账时刻。
nonisolated struct ChildRewardReceipt: Equatable, Sendable, Identifiable {
    let completionID: UUID
    let occurrenceID: UUID
    let title: String
    let completedAt: Date
    let settledAt: Date
    let timing: CompletionTiming
    let xp: Int
    let coins: Int

    var id: UUID { completionID }
}

extension ChildRewardReceipt {
    /// 纯展示预览值，不创建模型或写入正式容器。
    static var preview: Self {
        Self(
            completionID: UUID(), occurrenceID: UUID(), title: "认真读完一本书", completedAt: .distantPast,
            settledAt: .distantPast, timing: .beforeReminder, xp: 11, coins: 10)
    }

    static var previewZero: Self {
        Self(
            completionID: UUID(), occurrenceID: UUID(), title: "自己整理书包", completedAt: .distantPast,
            settledAt: .distantPast, timing: .afterReminder, xp: 0, coins: 0)
    }
}
