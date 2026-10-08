import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("宠物成长与喂食事务")
struct PetCareServiceTests {
    private let now = Date(timeIntervalSince1970: 1_791_421_200)

    @Test("有效XP阈值及最大整数精确派生等级", arguments: [0, 99, 100, 199, 200, Int.max])
    func levelThresholds(xp: Int) throws {
        #expect(try PetCareRules.level(effectiveXP: xp) == xp / 100 + 1)
        let context = try makeContext(xp: xp, coins: 0)
        let snapshot = try #require(try service(context).load(at: now))
        #expect(snapshot.level == xp / 100 + 1 && snapshot.xpInLevel == xp % 100)
        #expect(snapshot.xpToNextLevel == 100 - xp % 100)
        #expect(snapshot.bond == 0 && snapshot.mood == .calm && !snapshot.canFeed)
        #expect(!context.hasChanges)
    }

    @Test("负XP拒绝，不用溢出或错误等级兜底")
    func negativeXPIsRejected() {
        #expect(throws: PetCareError.invalidFacts) { try PetCareRules.level(effectiveXP: -1) }
    }

    @Test("无资料只读为空且喂食拒绝，不创建默认宠物")
    func missingProfileCannotFeed() throws {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        let care = service(context)
        #expect(try care.load(at: now) == nil)
        #expect(throws: PetCareError.notConfigured) { try care.feed(requestID: UUID(), at: now) }
        #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test("一次喂食原子扣五币增一亲密度，同ID重试不二扣")
    func feedingIsIdempotentAcrossServiceInstances() throws {
        let context = try makeContext(xp: 199, coins: 10)
        let id = UUID()
        let first = try service(context).feed(requestID: id, at: now)
        let repeated = try service(context).feed(requestID: id, at: now.addingTimeInterval(60))
        #expect(first.didInsert && !repeated.didInsert && first.createdAt == repeated.createdAt)
        let one = try #require(try service(context).load(at: now))
        #expect(one.coins == 5 && one.bond == 1 && one.mood == .happy && one.level == 2)
        _ = try service(context).feed(requestID: UUID(), at: now)
        let two = try #require(try service(context).load(at: now))
        #expect(two.coins == 0 && two.bond == 2 && !two.canFeed)
        #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
    }

    @Test("不足五币明确拒绝且无喂食或新消费", arguments: [0, 4])
    func insufficientBalance(coins: Int) throws {
        let context = try makeContext(coins: coins)
        #expect(throws: RewardLedgerError.insufficientCoins(required: 5, available: coins)) {
            try service(context).feed(requestID: UUID(), at: now)
        }
        #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 1)
        #expect(!context.hasChanges)
    }

    @Test("保存失败同时撤回扣款和喂食，原请求可重试", arguments: [false, true])
    func failedSaveRollsBackBothFacts(disk: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let id = UUID()
        let context: ModelContext
        if disk {
            // 先结束写入容器的作用域再重开；17不能在第二容器登记模型后继续向旧容器插入。
            try failAndCloseStore(at: url, id: id)
            context = ModelContext(try AppModelContainer.make(storeURL: url))
        } else {
            context = try makeContext(coins: 5)
            try verifyFailedSave(context, id: id)
        }
        #expect(try #require(try service(context).load(at: now)).coins == 5)
        #expect(try service(context).feed(requestID: id, at: now).didInsert)
        #expect(try #require(try service(context).load(at: now)).coins == 0)
    }

    private func failAndCloseStore(at url: URL, id: UUID) throws {
        let context = try makeContext(coins: 5, storeURL: url)
        try verifyFailedSave(context, id: id)
    }

    private func verifyFailedSave(_ context: ModelContext, id: UUID) throws {
        var saves = 0
        let care = service(context) { _ in
            saves += 1; throw CocoaError(.fileWriteUnknown)
        }
        #expect(throws: CocoaError.self) { try care.feed(requestID: id, at: now) }
        #expect(saves == 1 && !context.hasChanges)
        #expect(try #require(try service(context).load(at: now)).coins == 5)
        #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 0)
    }

    @Test("调用方脏草稿拒绝且不被保存或回滚")
    func unrelatedDraftSurvivesFailure() throws {
        let context = try makeContext()
        let settings = AppSettings()
        context.insert(settings)
        #expect(throws: PetCareError.pendingContextChanges) { try service(context).feed(requestID: UUID(), at: now) }
        #expect(context.hasChanges && context.insertedModelsArray.contains { $0 === settings })
        context.rollback()
    }

    @Test("已存在消费但缺喂食不补写或重复扣款")
    func orphanSpendConflicts() throws {
        let context = try makeContext(coins: 10)
        let id = UUID()
        _ = try RewardLedgerService(context: context).spendCoins(sourceID: id, cost: 5, at: now)
        #expect(throws: PetCareError.feedingConflict) { try service(context).feed(requestID: id, at: now) }
        #expect(try #require(try service(context).load(at: now)).coins == 5)
        #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 0)
    }

    @Test("缺扣款及非法喂食快照拒绝读取和继续写入", arguments: Array(0..<6))
    func corruptFeedingIsNotSilentlyDisplayed(kind: Int) throws {
        let context = try makeContext()
        let id = UUID()
        if kind != 0 { _ = try RewardLedgerService(context: context).spendCoins(sourceID: id, cost: 5, at: now) }
        context.insert(
            PetFeeding(
                id: id, petKey: kind == 1 ? "foreign" : Pet.defaultKey,
                foodID: kind == 2 ? "other" : "kibble", coinCost: kind == 3 ? 4 : 5,
                bondGain: kind == 4 ? 0 : 1, createdAt: kind == 5 ? now.addingTimeInterval(1) : now))
        try context.save()
        #expect(throws: PetCareError.invalidFacts) { try service(context).load(at: now) }
        #expect(throws: PetCareError.invalidFacts) { try service(context).feed(requestID: UUID(), at: now) }
        #expect(!context.hasChanges)
    }

    @Test("心情使用当地日界，跨日不衰减亲密度", arguments: ["Asia/Shanghai", "America/Los_Angeles"])
    func localDayMood(timeZoneID: String) throws {
        let context = try makeContext()
        let zone = try #require(TimeZone(identifier: timeZoneID))
        let care = PetCareService(context: context, calendar: Calendar(identifier: .gregorian), timeZone: zone)
        let feedingAt = try V0MigrationFixture.instant("2026-03-08T09:30:00Z")
        _ = try care.feed(requestID: UUID(), at: feedingAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let interval = try #require(calendar.dateInterval(of: .day, for: feedingAt))
        #expect(try #require(try care.load(at: interval.end.addingTimeInterval(-1))).mood == .happy)
        let next = try #require(try care.load(at: interval.end))
        #expect(next.mood == .calm && next.bond == 1 && next.coins == 5)
        if timeZoneID == "America/Los_Angeles" { #expect(interval.duration == 23 * 3600) }
    }

    @Test("回拨保留亲密度但未来事实不算今天开心，新喂食拒绝逆序")
    func clockRollback() throws {
        let context = try makeContext()
        let id = UUID()
        _ = try service(context).feed(requestID: id, at: now)
        let earlier = now.addingTimeInterval(-1)
        let snapshot = try #require(try service(context).load(at: earlier))
        #expect(snapshot.bond == 1 && snapshot.mood == .calm)
        #expect(throws: PetCareError.timeBeforeLatestFeeding) {
            try service(context).feed(requestID: UUID(), at: earlier)
        }
        #expect(try !service(context).feed(requestID: id, at: earlier).didInsert)
    }

    @Test("非有限时间拒绝", arguments: [Double.nan, .infinity, -.infinity])
    func invalidTime(value: Double) throws {
        let context = try makeContext()
        #expect(throws: PetCareError.invalidTimestamp) {
            try service(context).load(at: Date(timeIntervalSinceReferenceDate: value))
        }
    }

    @Test("XP冲正重算等级而不更改喂食亲密度")
    func reversalRecomputesLevel() throws {
        let context = try makeContext(xp: 99, coins: 10)
        let ledger = RewardLedgerService(context: context)
        let id = UUID()
        _ = try ledger.grantReward(sourceID: id, xp: 201, coins: 0, at: now)
        #expect(try #require(try service(context).load(at: now)).level == 4)
        _ = try service(context).feed(requestID: UUID(), at: now)
        _ = try ledger.reverseReward(sourceID: id, at: now)
        let snapshot = try #require(try service(context).load(at: now))
        #expect(snapshot.level == 1 && snapshot.bond == 1 && snapshot.coins == 5)
    }

    @Test("真实磁盘重启保持扣款亲密度及幂等")
    func diskReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let id = UUID()
        try seedFeeding(at: url, id: id)
        for _ in 0..<3 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let snapshot = try #require(try service(context).load(at: now))
            #expect(snapshot.coins == 5 && snapshot.bond == 1 && snapshot.mood == .happy)
            #expect(try !service(context).feed(requestID: id, at: now).didInsert)
            #expect(try context.fetchCount(FetchDescriptor<PetFeeding>()) == 1)
            #expect(!context.hasChanges)
        }
    }

    private func service(_ context: ModelContext, save: @escaping (ModelContext) throws -> Void = { try $0.save() })
        -> PetCareService
    {
        PetCareService(context: context, calendar: Calendar(identifier: .gregorian), timeZone: .gmt, saveChanges: save)
    }

    private func makeContext(xp: Int = 0, coins: Int = 10, storeURL: URL? = nil) throws -> ModelContext {
        let container =
            try storeURL.map { try AppModelContainer.make(storeURL: $0) } ?? AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try FamilyProfileService(context: context).save(FamilyProfileNames(childNickname: "合成孩子", petName: "合成小狗"))
        _ = try RewardLedgerService(context: context).grantReward(
            sourceID: UUID(), xp: xp, coins: coins, at: now.addingTimeInterval(-1))
        return context
    }

    private func seedFeeding(at url: URL, id: UUID) throws {
        let context = try makeContext(storeURL: url)
        _ = try service(context).feed(requestID: id, at: now)
    }
}
