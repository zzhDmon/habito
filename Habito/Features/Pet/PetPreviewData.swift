import Foundation

/// 预览仅提供内存值，绝不写正式容器；合成数据与正式组合根完全分开。
@MainActor
enum PetPreviewData {
    static func snapshot() throws -> PetCareSnapshot {
        PetCareSnapshot(
            names: try FamilyProfileNames(childNickname: "合成孩子", petName: "奶油小毛球"),
            effectiveXP: 195, level: 2, xpInLevel: 95, xpToNextLevel: 5, coins: 12, bond: 3, mood: .happy)
    }

    static func model(kind: Int) -> PetProfileViewModel {
        PetProfileViewModel(
            loadSnapshot: { _ in
                if kind == 2 { throw PetCareError.invalidFacts }
                return kind == 0 ? nil : try snapshot()
            }, feedPet: { _, _ in throw PetCareError.notConfigured }, now: { Date(timeIntervalSince1970: 0) })
    }
}
