import Foundation
import SwiftData

/// 成功喂食的不可变审计事实；稳定请求ID同时关联Coin消费，不能因改名字或任务删除而消失。
///
/// `@Model`由主actor上下文管理；成本与效果存快照，未来调整价格不重算历史亲密度。
@Model
final class PetFeeding {
    @Attribute(.unique) private(set) var id: UUID
    private(set) var petKey: String
    private(set) var foodID: String
    private(set) var coinCost: Int
    private(set) var bondGain: Int
    private(set) var createdAt: Date

    /// 仅构造未保存事实；输入校验、扣款、幂等及统一保存由PetCareService负责。
    init(id: UUID, petKey: String, foodID: String, coinCost: Int, bondGain: Int, createdAt: Date) {
        self.id = id
        self.petKey = petKey
        self.foodID = foodID
        self.coinCost = coinCost
        self.bondGain = bondGain
        self.createdAt = createdAt
    }
}
