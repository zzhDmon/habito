import Foundation
import SwiftData

// 冻结自 cdce127 的结构 6.0.0；历史字段与关系不能随当前模型演进。
extension HabitoSchemaV5 {
    /// Coin 收支审计事实；余额由有效交易派生，完成/消费图不拥有此记录。
    ///
    /// - Important: private(set) 避免外部改写交易。业务入口仍需验证方向、余额和重复键，
    ///   unique 不能替代原子性/幂等；本阶段未开放发奖或消费入口。
    @Model
    final class CoinTransaction {
        @Attribute(.unique) private(set) var id: UUID
        @Attribute(.unique) private(set) var businessKey: String
        private(set) var sourceID: UUID
        private(set) var kindRawValue: String
        private(set) var amount: Int
        private(set) var reversalOfBusinessKey: String?
        private(set) var createdAt: Date

        /// 构造尚未保存的收支；稳定来源 ID 可反查，不能靠删除消费来纠错。
        ///
        /// - Parameters:
        ///   - id: 存储身份。
        ///   - businessKey: 来源事件与资产类型的稳定幂等键。
        ///   - sourceID: 奖励完成或消费事件的稳定 ID。
        ///   - kind: 收入、消费或冲正。
        ///   - amount: 有符号整数 Coin，收入为正，消费/奖励冲正为负。
        ///   - reversalOfBusinessKey: 冲正关联原交易，普通奖励/消费为空。
        ///   - createdAt: 注入的绝对写入时间。
        init(
            id: UUID = UUID(), businessKey: String, sourceID: UUID, kind: CoinTransactionKind,
            amount: Int, reversalOfBusinessKey: String? = nil, createdAt: Date
        ) {
            self.id = id
            self.businessKey = businessKey
            self.sourceID = sourceID
            self.kindRawValue = kind.rawValue
            self.amount = amount
            self.reversalOfBusinessKey = reversalOfBusinessKey
            self.createdAt = createdAt
        }

        var kind: CoinTransactionKind? { CoinTransactionKind(rawValue: kindRawValue) }
    }
}
