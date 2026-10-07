import Foundation

/// 将一次性保存收据转成只读展示值，避免 View 用余额或任务当前配置推测本次到账。
///
/// 此类型不读取数据库，也不判断“是否应发奖”；事件是否新保存成功仍由原页面用例负责。
/// 零金额不生成货币卡，旧历史未知自主性不显示自主徽标。
nonisolated struct TaskSessionFeedbackPresentation: Equatable, Identifiable, Sendable {
    let id: UUID
    let tone: TaskSessionFeedbackTone
    let xp: Int?
    let coins: Int?

    init(feedback: TaskSessionCompletionFeedback) {
        id = feedback.id
        switch feedback {
        case .submitted:
            tone = .submitted
            xp = nil
            coins = nil
        case let .completed(receipt):
            tone = receipt.timing == .beforeReminder ? .autonomous : .completed
            xp = receipt.xp > 0 ? receipt.xp : nil
            coins = receipt.coins > 0 ? receipt.coins : nil
        }
    }

    var hasReward: Bool { xp != nil || coins != nil }

    /// 审核后反馈直接使用已验证完成快照；不伪造一次新的完成或重新计算金额。
    init(receipt: ChildRewardReceipt) {
        id = receipt.id
        tone = receipt.timing == .beforeReminder ? .autonomous : .completed
        xp = receipt.xp > 0 ? receipt.xp : nil
        coins = receipt.coins > 0 ? receipt.coins : nil
    }
}
