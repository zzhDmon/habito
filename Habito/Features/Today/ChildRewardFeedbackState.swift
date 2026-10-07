/// 首页审核收据状态独立于今日任务和资产；读取失败不伪装成“没有奖励”。
nonisolated enum ChildRewardFeedbackState: Equatable, Sendable {
    case idle
    case receipt(ChildRewardReceipt)
    case failed
}
