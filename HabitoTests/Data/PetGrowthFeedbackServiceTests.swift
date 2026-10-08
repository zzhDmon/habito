import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("真实升级领取与持久化去重")
struct PetGrowthFeedbackServiceTests {
    private let now = Date(timeIntervalSince1970: 1_791_421_200)

    @Test("未配置不建观察点，首次已有XP只建当前基线", arguments: [false, true])
    func initialBaseline(configured: Bool) throws {
        let context = try context(configured: configured)
        let result = try PetGrowthFeedbackService(context: context).observe()
        if configured {
            #expect(result == PetGrowthObservation(previousLevel: nil, currentLevel: 4))
            #expect(result?.didLevelUp == false)
        } else {
            #expect(result == nil)
        }
        #expect(try context.fetchCount(FetchDescriptor<PetGrowthCheckpoint>()) == (configured ? 1 : 0))
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
    }

    @Test("跨多级一次领取，刷新不重复保存，纠错降级不庆祝")
    func crossingAndReversal() throws {
        let context = try context()
        var saves = 0
        let service = PetGrowthFeedbackService(context: context) { context in
            saves += 1; try context.save()
        }
        _ = try service.observe()
        let ledger = RewardLedgerService(context: context)
        let id = UUID()
        _ = try ledger.grantReward(sourceID: id, xp: 201, coins: 0, at: now)
        let upgrade = try #require(try service.observe())
        #expect(upgrade.previousLevel == 4 && upgrade.currentLevel == 6 && upgrade.didLevelUp)
        #expect(saves == 2)
        #expect(try service.observe()?.didLevelUp == false)
        #expect(saves == 2)
        _ = try ledger.reverseReward(sourceID: id, at: now)
        let downgrade = try #require(try service.observe())
        #expect(downgrade.currentLevel == 4 && !downgrade.didLevelUp && saves == 3)
        #expect(try ledger.balance().effectiveXP == 300)
    }

    @Test("首次或更新保存失败不丢领取资格，重试才持久化", arguments: [false, true])
    func failedSaveRetainsEligibility(existing: Bool) throws {
        let context = try context()
        if existing {
            _ = try PetGrowthFeedbackService(context: context).observe()
            _ = try RewardLedgerService(context: context).grantReward(sourceID: UUID(), xp: 100, coins: 0, at: now)
        }
        let failed = PetGrowthFeedbackService(context: context) { _ in throw CocoaError(.fileWriteUnknown) }
        #expect(throws: CocoaError.self) { try failed.observe() }
        #expect(!context.hasChanges)
        let stored = try context.fetch(FetchDescriptor<PetGrowthCheckpoint>())
        #expect(stored.count == (existing ? 1 : 0))
        if existing { #expect(stored.first?.observedLevel == 4) }
        let retried = try #require(try PetGrowthFeedbackService(context: context).observe())
        #expect(retried.didLevelUp == existing)
    }

    @Test("坏观察点或外部草稿明确拒绝且不修复", arguments: [0, -1, Int.max])
    func invalidCheckpoint(level: Int) throws {
        let context = try context()
        context.insert(PetGrowthCheckpoint(petKey: Pet.defaultKey, observedLevel: level))
        #expect(throws: PetCareError.pendingContextChanges) { try PetGrowthFeedbackService(context: context).observe() }
        #expect(context.hasChanges)
        try context.save()
        #expect(throws: PetCareError.invalidFacts) { try PetGrowthFeedbackService(context: context).observe() }
        #expect(try context.fetch(FetchDescriptor<PetGrowthCheckpoint>()).first?.observedLevel == level)
    }

    @Test("真实磁盘升级领取后多次重开不再播也不改XP")
    func restartDoesNotReplay() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try claim(at: url)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let observation = try #require(try PetGrowthFeedbackService(context: context).observe())
            #expect(observation.currentLevel == 5 && !observation.didLevelUp)
            #expect(try RewardLedgerService(context: context).balance().effectiveXP == 400)
            #expect(!context.hasChanges)
        }
    }

    private func context(configured: Bool = true, storeURL: URL? = nil) throws -> ModelContext {
        let container =
            try storeURL.map { try AppModelContainer.make(storeURL: $0) } ?? AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if configured {
            try FamilyProfileService(context: context).save(FamilyProfileNames(childNickname: "合成孩子", petName: "合成小狗"))
        }
        _ = try RewardLedgerService(context: context).grantReward(sourceID: UUID(), xp: 300, coins: 0, at: now)
        return context
    }

    private func claim(at url: URL) throws {
        let context = try context(storeURL: url)
        let service = PetGrowthFeedbackService(context: context)
        _ = try service.observe()
        _ = try RewardLedgerService(context: context).grantReward(sourceID: UUID(), xp: 100, coins: 0, at: now)
        #expect(try service.observe()?.didLevelUp == true)
    }
}
