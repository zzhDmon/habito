/// 已成功保存的等级观察结果；nil旧级表示首次建立基线，不代表发生了升级。
nonisolated struct PetGrowthObservation: Equatable, Sendable {
    let previousLevel: Int?
    let currentLevel: Int

    var didLevelUp: Bool { previousLevel.map { currentLevel > $0 } ?? false }
}
