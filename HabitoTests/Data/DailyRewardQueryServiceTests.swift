import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("今日所得只读查询")
struct DailyRewardQueryServiceTests {
    @Test("当天边界由注入时区决定，未来交易不提前显示", arguments: ["Asia/Shanghai", "America/Los_Angeles"])
    func localDayAndFutureBoundary(zone: String) throws {
        let fixture = try TodayQueryFixture()
        let timeZone = try #require(TimeZone(identifier: zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = try V0MigrationFixture.instant("2026-09-23T12:00:00Z")
        let day = try #require(calendar.dateInterval(of: .day, for: now))
        let ledger = RewardLedgerService(context: fixture.context)
        for (index, date) in [day.start.addingTimeInterval(-1), day.start, now, now.addingTimeInterval(1), day.end]
            .enumerated()
        {
            _ = try ledger.grantReward(sourceID: id(index), xp: index + 1, coins: (index + 1) * 2, at: date)
        }
        let query = DailyRewardQueryService(context: fixture.context, calendar: calendar, timeZone: timeZone)
        #expect(try query.summary(at: now) == DailyRewardSummary(earnedXP: 5, earnedCoins: 10))
        #expect(try query.summary(at: day.end) == DailyRewardSummary(earnedXP: 5, earnedCoins: 10))
        #expect(!fixture.context.hasChanges)
    }

    @Test("夏令时短日长日均包含当地当天两端", arguments: ["2026-03-08T19:00:00Z", "2026-11-01T20:00:00Z"])
    func daylightSavingDay(iso: String) throws {
        let fixture = try TodayQueryFixture()
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = try #require(calendar.dateInterval(of: .day, for: V0MigrationFixture.instant(iso)))
        #expect(day.duration == (iso.contains("03-08") ? 23 : 25) * 3600)
        let ledger = RewardLedgerService(context: fixture.context)
        for (index, date) in [day.start.addingTimeInterval(-1), day.start, day.end.addingTimeInterval(-1), day.end]
            .enumerated()
        {
            _ = try ledger.grantReward(sourceID: id(index), xp: 1, coins: 2, at: date)
        }
        #expect(
            try DailyRewardQueryService(context: fixture.context, calendar: calendar, timeZone: zone)
                .summary(at: day.end.addingTimeInterval(-0.5)) == DailyRewardSummary(earnedXP: 2, earnedCoins: 4))
    }

    @Test("空账本与旧完成不补奖，零奖励依然是零", arguments: [false, true])
    func noInventedIncome(legacy: Bool) throws {
        let fixture = try TodayQueryFixture()
        if legacy {
            let occurrence = fixture.makeOccurrence(title: "旧完成", scheduledAt: fixture.now, status: .completed)
            fixture.addCompletion(to: occurrence, at: fixture.now)
            try fixture.context.save()
        }
        let query = query(fixture)
        #expect(try query.summary(at: fixture.now) == DailyRewardSummary(earnedXP: 0, earnedCoins: 0))
        _ = try RewardLedgerService(context: fixture.context).grantReward(
            sourceID: id(1), xp: 0, coins: 0, at: fixture.now)
        for _ in 0..<3 {
            #expect(try query.summary(at: fixture.now) == DailyRewardSummary(earnedXP: 0, earnedCoins: 0))
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
        #expect(!fixture.context.hasChanges)
    }

    @Test("真实跨日审核按通过入账日统计，重复审核不增加所得")
    func approvalUsesSettlementDay() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let submission = try fixture.item(for: occurrence)
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let query = DailyRewardQueryService(
            context: fixture.context, calendar: Calendar(identifier: .gregorian), timeZone: zone)
        #expect(try query.summary(at: fixture.now) == DailyRewardSummary(earnedXP: 0, earnedCoins: 0))
        let tomorrow = fixture.now.addingTimeInterval(86400)
        let service = TaskSubmissionReviewService(context: fixture.context)
        for _ in 0..<2 { _ = try service.approve(occurrence, submissionID: submission.id, at: tomorrow) }
        #expect(try query.summary(at: tomorrow) == DailyRewardSummary(earnedXP: 11, earnedCoins: 10))
        #expect(try query.summary(at: fixture.now) == DailyRewardSummary(earnedXP: 0, earnedCoins: 0))
        #expect(!fixture.context.hasChanges)
    }

    @Test("消费不减所得，跨日或当日冲正排除原奖励且回拨不复活", arguments: [0.0, 86400.0])
    func spendAndReversal(offset: TimeInterval) throws {
        let fixture = try TodayQueryFixture()
        let ledger = RewardLedgerService(context: fixture.context)
        _ = try ledger.grantReward(sourceID: id(1), xp: 11, coins: 7, at: fixture.now)
        _ = try ledger.grantReward(sourceID: id(2), xp: 5, coins: 5, at: fixture.now)
        _ = try ledger.spendCoins(sourceID: id(3), cost: 3, at: fixture.now)
        #expect(try query(fixture).summary(at: fixture.now) == DailyRewardSummary(earnedXP: 16, earnedCoins: 12))
        #expect(try ledger.balance().coins == 9)
        _ = try ledger.reverseReward(sourceID: id(1), at: fixture.now.addingTimeInterval(offset))
        #expect(try query(fixture).summary(at: fixture.now) == DailyRewardSummary(earnedXP: 5, earnedCoins: 5))
        #expect(try ledger.balance().coins == 2)
        #expect(!fixture.context.hasChanges)
    }

    @Test("余额合法但当日收入超出Int时明确拒绝，不截断金额")
    func incomeOverflowAfterSpending() throws {
        let fixture = try TodayQueryFixture()
        let ledger = RewardLedgerService(context: fixture.context)
        _ = try ledger.grantReward(sourceID: id(1), xp: 0, coins: Int.max, at: fixture.now)
        _ = try ledger.spendCoins(sourceID: id(2), cost: Int.max, at: fixture.now)
        _ = try ledger.grantReward(sourceID: id(3), xp: 0, coins: 1, at: fixture.now)
        #expect(try ledger.balance().coins == 1)
        #expect(throws: RewardLedgerError.integerOverflow) { try query(fixture).summary(at: fixture.now) }
        #expect(!fixture.context.hasChanges)
    }

    @Test("脏上下文拒绝且保留调用方编辑，保存后才显示到账")
    func pendingChanges() throws {
        let fixture = try TodayQueryFixture()
        fixture.context.autosaveEnabled = false
        _ = try RewardLedgerService(context: fixture.context).stageReward(
            sourceID: id(1), xp: 11, coins: 7, at: fixture.now)
        #expect(throws: RewardLedgerError.pendingContextChanges) { try query(fixture).summary(at: fixture.now) }
        #expect(fixture.context.hasChanges)
        try fixture.context.save()
        #expect(try query(fixture).summary(at: fixture.now) == DailyRewardSummary(earnedXP: 11, earnedCoins: 7))
    }

    @Test("昨天损坏交易同样拒绝，不因当天筛选隐藏账本损坏")
    func corruptOlderLedger() throws {
        let fixture = try TodayQueryFixture()
        let key = RewardLedgerKey.xpReward(id(1))
        fixture.context.insert(
            XPTransaction(
                businessKey: key, sourceID: id(1), kind: .reward, amount: 1,
                createdAt: fixture.now.addingTimeInterval(-86400)))
        try fixture.context.save()
        #expect(throws: RewardLedgerError.corruptLedger(key)) { try query(fixture).summary(at: fixture.now) }
        #expect(!fixture.context.hasChanges)
    }

    @Test("非有限时间拒绝，不当作空收入", arguments: [Double.infinity, -Double.infinity, Double.nan])
    func invalidTime(value: Double) throws {
        let fixture = try TodayQueryFixture()
        #expect(throws: RewardLedgerError.invalidTimestamp) {
            try query(fixture).summary(at: Date(timeIntervalSinceReferenceDate: value))
        }
    }

    private func query(_ fixture: TodayQueryFixture) -> DailyRewardQueryService {
        DailyRewardQueryService(context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(value)))
    }
}
