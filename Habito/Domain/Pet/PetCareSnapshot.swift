/// 真实名字、有效XP及喂食审计的不可变投影，View不自行查账或计算日界。
nonisolated struct PetCareSnapshot: Equatable, Sendable {
    let names: FamilyProfileNames
    let effectiveXP: Int
    let level: Int
    let xpInLevel: Int
    let xpToNextLevel: Int
    let coins: Int
    let bond: Int
    let mood: PetMood

    var canFeed: Bool { coins >= PetCareRules.foodCost }
}
