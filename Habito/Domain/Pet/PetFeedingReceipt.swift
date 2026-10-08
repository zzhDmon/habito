import Foundation

/// 只在统一保存成功或已存在同请求事实时返回；didInsert=false不得再播一次喂食反馈。
nonisolated struct PetFeedingReceipt: Equatable, Sendable {
    let id: UUID
    let coinCost: Int
    let bondGain: Int
    let createdAt: Date
    let didInsert: Bool
}
