/// 宠物读写的明确失败边界；账本错误原样传播，让UI区分余额不足与保存失败。
nonisolated enum PetCareError: Error, Equatable, Sendable {
    case notConfigured
    case invalidFacts
    case pendingContextChanges
    case invalidTimestamp
    case timeBeforeLatestFeeding
    case feedingConflict
}
