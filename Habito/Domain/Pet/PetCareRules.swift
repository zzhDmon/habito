/// DEC-033已确认的首版宠物规则；集中常量便于未来显式版本演进，历史喂食仍读取自身快照。
nonisolated enum PetCareRules {
    static let xpPerLevel = 100
    static let foodID = "kibble"
    static let foodCost = 5
    static let feedingBondGain = 1

    /// 除法后加一避免计算下一阈值时溢出；最大Int XP也能得到有效等级和剩余XP。
    static func level(effectiveXP: Int) throws -> Int {
        guard effectiveXP >= 0 else { throw PetCareError.invalidFacts }
        return effectiveXP / xpPerLevel + 1
    }
}
