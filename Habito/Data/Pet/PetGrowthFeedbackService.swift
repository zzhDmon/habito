import SwiftData

/// 只保存反馈观察点，不发奖、不维护第二份等级；真实等级仍来自同一个XP账本。
@MainActor
struct PetGrowthFeedbackService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 在儿童可见且无家长草稿时显式调用；先保存观察点，再把升级交给UI。
    /// - Returns: 没有家庭资料时为nil；首次结果previousLevel为nil，不能补播历史升级。
    /// - Throws: 脏上下文、坏资料/账本/观察点或保存失败；失败保留旧点，可安全重试。
    /// - Important: 采用至多一次领取；极端情况下保存后、展示前进程退出会略过这次装饰反馈，绝不影响XP。
    func observe() throws -> PetGrowthObservation? {
        guard !context.hasChanges else { throw PetCareError.pendingContextChanges }
        let names = try FamilyProfileService(context: context).load()
        let rows = try context.fetch(FetchDescriptor<PetGrowthCheckpoint>())
        guard rows.count <= 1 else { throw PetCareError.invalidFacts }
        if let row = rows.first {
            guard row.petKey == Pet.defaultKey, row.observedLevel >= 1,
                row.observedLevel <= Int.max / PetCareRules.xpPerLevel + 1
            else { throw PetCareError.invalidFacts }
        }
        guard names != nil else {
            guard rows.isEmpty else { throw PetCareError.invalidFacts }
            return nil
        }
        let level = try PetCareRules.level(effectiveXP: RewardLedgerService(context: context).balance().effectiveXP)
        let existing = rows.first
        let previous = existing?.observedLevel
        let result = PetGrowthObservation(previousLevel: previous, currentLevel: level)
        if previous == level { return result }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        if let existing {
            existing.observe(level: level)
        } else {
            context.insert(PetGrowthCheckpoint(petKey: Pet.defaultKey, observedLevel: level))
        }
        do {
            try saveChanges(context)
            return result
        } catch {
            if let previous { existing?.observe(level: previous) }
            context.rollback()
            throw error
        }
    }
}
