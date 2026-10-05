import Foundation
import SwiftData

/// XP 审计事实；外部用例只能创建，不能直接修改已创建的金额或来源。
///
/// - Important: 唯一业务键只是数据库兜底；SwiftData unique 碰撞可能 upsert，
///   写用例仍必须先比较已有输入，不能依赖其自动去重。负数仅由明确纠错用例创建。
///   来源用稳定 UUID 而非级联关系，删除任务图不能删除已发生的交易历史。
@Model
final class XPTransaction {
    @Attribute(.unique) private(set) var id: UUID
    @Attribute(.unique) private(set) var businessKey: String
    private(set) var sourceID: UUID
    private(set) var kindRawValue: String
    private(set) var amount: Int
    private(set) var reversalOfBusinessKey: String?
    private(set) var createdAt: Date

    /// 构造尚未保存的交易；输入合法性由下一阶段唯一账本写入口校验。
    ///
    /// - Parameters:
    ///   - id: 存储身份，与可重试的业务键分离。
    ///   - businessKey: 来源事件与资产类型的稳定幂等键。
    ///   - sourceID: 对应完成事件的稳定 ID，不通过模型关系级联删除。
    ///   - kind: 正常奖励或纠错冲正。
    ///   - amount: 有符号整数 XP，不使用浮点货币。
    ///   - reversalOfBusinessKey: 冲正关联的原交易键，正常收入为空。
    ///   - createdAt: 调用方注入的绝对写入时间，不读取真实时钟。
    init(
        id: UUID = UUID(), businessKey: String, sourceID: UUID, kind: XPTransactionKind,
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

    var kind: XPTransactionKind? { XPTransactionKind(rawValue: kindRawValue) }
}
