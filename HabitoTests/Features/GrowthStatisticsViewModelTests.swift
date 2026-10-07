import Foundation
import SwiftData
import Testing
@testable import Habito

/// 页面时钟由主actor闭包注入；测试不等待计时器、不读取设备日期或家庭库。
@MainActor
struct GrowthStatisticsViewModelTests {
    @Test("构造保持idle、不查询脏库；关闭后清除历史和窗口")
    func constructionAndResetDoNotReadHistory() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        occurrence.titleSnapshot = "未保存"
        let model = try model(fixture)
        #expect(model.state == .idle && model.period == .week)
        #expect(fixture.context.hasChanges)
        model.load()
        #expect(model.state == .failed && fixture.context.hasChanges)
        try fixture.context.save()
        model.select(.month)
        #expect(try snapshot(model).days.count == 30)
        model.reset()
        #expect(model.state == .idle && model.period == .week && !fixture.context.hasChanges)
    }

    @Test("窗口切换保持样本归属，不按审核到账或平均每日比例", arguments: GrowthStatisticsPeriod.allCases)
    func selectedWindowReadsActualHistory(period: GrowthStatisticsPeriod) throws {
        let fixture = try ParentReviewFixture()
        for day in ["2026-08-25", "2026-09-10", "2026-09-20", "2026-09-23", "2026-09-24"] {
            _ = try makeOccurrence(fixture, day: day)
        }
        let model = try model(fixture)
        model.select(period)
        let result = try snapshot(model)
        #expect(result.period == period && model.period == period && result.days.count == period.rawValue)
        let expected =
            switch period {
            case .week: 2
            case .fortnight: 3
            case .month: 4
            }
        #expect(result.counts.eligible == expected && result.counts.completionRate == 0)
        #expect(result.counts.autonomyRate == nil && result.end.dateKey == "2026-09-23")
        try expectReadOnly(fixture)
    }

    @Test("保存后刷新真实完成和撤销，不缓存旧分子")
    func reloadReflectsCompletionAndUndo() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        let model = try model(fixture, at: fixture.now.addingTimeInterval(2))
        model.load()
        #expect(try snapshot(model).counts.completionRate == 0)
        let result = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        model.load()
        let completed = try snapshot(model).counts
        #expect(completed.completionRate == 1 && completed.autonomyRate == 1 && completed.childConfirmed == 1)
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: result.completionID, at: fixture.now.addingTimeInterval(1))
        model.load()
        #expect(try snapshot(model).counts.completed == 0)
        #expect(try snapshot(model).counts.autonomyRate == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 2)
        #expect(!fixture.context.hasChanges)
    }

    @Test("跨午夜重读新今天，未来实例成为今日，旧日不复制")
    func injectedClockMovesAcrossMidnight() throws {
        let fixture = try ParentReviewFixture()
        _ = try makeOccurrence(fixture)
        _ = try makeOccurrence(fixture, day: "2026-09-24")
        var now = fixture.now
        let service = try service(fixture)
        let model = GrowthStatisticsViewModel(service: service, now: { now })
        let overview = ParentTodayOverviewViewModel(service: service, now: { now })
        model.load()
        overview.load()
        #expect(try snapshot(model).counts.eligible == 1)
        #expect(try day(overview).date.dateKey == "2026-09-23")
        now = now.addingTimeInterval(86_400)
        model.load()
        overview.load()
        #expect(try snapshot(model).end.dateKey == "2026-09-24")
        #expect(try snapshot(model).counts.eligible == 2)
        #expect(try day(overview).date.dateKey == "2026-09-24" && day(overview).counts.eligible == 1)
        try expectReadOnly(fixture)
    }

    @Test("无样本与有样本零完成不同，不产生假比例")
    func noSamplesAreDifferentFromZero() throws {
        let fixture = try ParentReviewFixture()
        let model = try model(fixture)
        let overview = try overview(fixture)
        model.load()
        overview.load()
        #expect(try snapshot(model).counts.completionRate == nil && day(overview).counts.completionRate == nil)
        _ = try makeOccurrence(fixture)
        model.load()
        overview.load()
        #expect(try snapshot(model).counts.completionRate == 0 && day(overview).counts.completionRate == 0)
        #expect(try day(overview).counts.autonomyRate == nil)
        try expectReadOnly(fixture)
    }

    @Test("坏审计或脏上下文撤下旧比例，修复后同窗口可重试", arguments: [false, true])
    func failedReadRemovesOldContentAndCanRetry(dirty: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        let model = try model(fixture)
        let overview = try overview(fixture)
        model.select(.fortnight)
        overview.load()
        occurrence.statusRawValue = "broken"
        if !dirty { try fixture.context.save() }
        model.load()
        overview.load()
        #expect(model.state == .failed && overview.state == .failed && model.period == .fortnight)
        #expect(fixture.context.hasChanges == dirty && occurrence.statusRawValue == "broken")
        occurrence.statusRawValue = TaskOccurrenceStatus.pending.rawValue
        try fixture.context.save()
        model.load()
        overview.load()
        #expect(try snapshot(model).period == .fortnight && day(overview).counts.eligible == 1)
        try expectReadOnly(fixture)
    }

    @Test("今日来源和自主性分开，待验收/跳过/旧unknown分母准确")
    func overviewKeepsSourcesAndTimingSeparate() throws {
        let fixture = try ParentReviewFixture()
        let child = try makeOccurrence(fixture)
        _ = try TaskCompletionService(context: fixture.context).complete(child, at: fixture.now, source: .childManual)
        let corrected = try makeOccurrence(fixture)
        _ = try TaskCompletionService(context: fixture.context).complete(
            corrected, at: fixture.now.addingTimeInterval(60), source: .parentCorrection)
        let old = try makeOccurrence(fixture)
        _ = try TaskProgressService(context: fixture.context).complete(old, at: fixture.now, source: .childManual)
        let approved = try fixture.makeWaiting()
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            approved, submissionID: fixture.item(for: approved).id, at: fixture.now.addingTimeInterval(1))
        _ = try fixture.makeWaiting(id: UUID(), day: "2026-09-22")
        let waitingToday = try makeOccurrence(fixture, verification: .parentApproval)
        _ = try TaskSubmissionService(context: fixture.context).submit(waitingToday, at: fixture.now)
        let skipped = try makeOccurrence(fixture)
        skipped.statusRawValue = TaskOccurrenceStatus.skipped.rawValue
        try fixture.context.save()
        let model = try overview(fixture, at: fixture.now.addingTimeInterval(61))
        model.load()
        let counts = try day(model).counts
        #expect(counts.eligible == 5 && counts.completed == 4 && counts.awaitingReview == 1 && counts.skipped == 1)
        #expect(counts.childConfirmed == 2 && counts.parentApproved == 1 && counts.parentCorrected == 1)
        #expect(counts.knownTiming == 3 && counts.autonomous == 2 && counts.unknownTiming == 1)
        #expect(counts.completionRate == 0.8 && counts.autonomyRate == 2.0 / 3)
        #expect(!fixture.context.hasChanges)
    }

    @Test("今日查询隔离坏旧日，窗口查询仍明确失败而不忽略坏历史")
    func overviewIsIsolatedFromOtherDays() throws {
        let fixture = try ParentReviewFixture()
        _ = try makeOccurrence(fixture)
        let old = try makeOccurrence(fixture, day: "2026-09-22")
        old.statusRawValue = "broken"
        try fixture.context.save()
        let overview = try overview(fixture)
        let model = try model(fixture)
        overview.load()
        model.load()
        #expect(try day(overview).counts.eligible == 1 && model.state == .failed)
        overview.reset()
        #expect(overview.state == .idle && !fixture.context.hasChanges)
    }

    @Test("显式时区决定今日概况，非法时钟不保留旧日期")
    func overviewUsesBusinessTimeZoneAndRejectsClock() throws {
        let fixture = try ParentReviewFixture()
        _ = try makeOccurrence(fixture, day: "2026-09-22")
        _ = try makeOccurrence(fixture)
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var now = fixture.now
        let query = GrowthStatisticsQueryService(
            context: fixture.context, calendar: .init(identifier: .gregorian), timeZone: zone)
        let model = ParentTodayOverviewViewModel(service: query, now: { now })
        model.load()
        #expect(try day(model).date.dateKey == "2026-09-22" && day(model).counts.eligible == 1)
        now = Date(timeIntervalSinceReferenceDate: .nan)
        model.load()
        #expect(model.state == .failed)
        try expectReadOnly(fixture)
    }

    private func service(_ fixture: ParentReviewFixture) throws -> GrowthStatisticsQueryService {
        GrowthStatisticsQueryService(
            context: fixture.context, calendar: .init(identifier: .gregorian),
            timeZone: try #require(TimeZone(secondsFromGMT: 0)))
    }

    private func model(_ fixture: ParentReviewFixture, at date: Date? = nil) throws -> GrowthStatisticsViewModel {
        GrowthStatisticsViewModel(service: try service(fixture), now: { date ?? fixture.now })
    }

    private func overview(_ fixture: ParentReviewFixture, at date: Date? = nil) throws -> ParentTodayOverviewViewModel {
        ParentTodayOverviewViewModel(service: try service(fixture), now: { date ?? fixture.now })
    }

    private func snapshot(_ model: GrowthStatisticsViewModel) throws -> GrowthStatisticsSnapshot {
        guard case let .loaded(value) = model.state else { throw NSError(domain: "SyntheticStatisticsState", code: 1) }
        return value
    }

    private func day(_ model: ParentTodayOverviewViewModel) throws -> GrowthStatisticsDay {
        guard case let .loaded(value) = model.state else { throw NSError(domain: "SyntheticOverviewState", code: 1) }
        return value
    }

    private func makeOccurrence(
        _ fixture: ParentReviewFixture, day: String = "2026-09-23",
        verification: TaskVerificationType = .selfConfirm
    ) throws -> TaskOccurrence {
        let occurrence = TaskOccurrence(
            templateID: UUID(), date: try LocalDate(dateKey: day),
            scheduledAt: fixture.now.addingTimeInterval(60), titleSnapshot: "合成统计页面任务",
            iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            sourceRevision: 1, createdAt: fixture.now, updatedAt: fixture.now,
            verificationTypeSnapshot: verification, xpRewardSnapshot: 11, coinRewardSnapshot: 7,
            activeBonusCoinSnapshot: 3)
        fixture.context.insert(occurrence)
        try fixture.context.save()
        return occurrence
    }

    private func expectReadOnly(_ fixture: ParentReviewFixture) throws {
        #expect(!fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }
}
