import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Habito

/// 来源/自主性展示必须来自不同保存字段；用真实事务复核查询而不是靠文案猜业务。
@MainActor
struct ParentTodayStatisticsTests {
    @Test("三个完成来源与三种自主性展示独立", arguments: CompletionSource.allCases, CompletionTiming.allCases)
    func sourceAndTimingPresentationAreIndependent(source: CompletionSource, timing: CompletionTiming) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "合成行", scheduledAt: fixture.now, status: .completed)
        fixture.addCompletion(to: occurrence, at: fixture.now)
        try fixture.context.save()
        let queried = try TodayTaskQueryService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone
        )
        .item(id: occurrence.id, at: fixture.now)
        let completion = TodayTaskCompletion(
            id: UUID(), completedAt: fixture.now, activeDurationSeconds: 0,
            source: source, timing: timing)
        let item = TodayTaskItem(
            id: queried.id, date: queried.date, scheduledAt: queried.scheduledAt,
            title: queried.title, iconName: queried.iconName, colorToken: queried.colorToken,
            targetDurationSeconds: queried.targetDurationSeconds, status: .completed, origin: queried.origin,
            activeSessionState: nil, activeDurationSeconds: 0, completion: completion)
        let value = ParentTodayTaskPresentation(item: item)
        let sourceKey: LocalizedStringKey =
            switch source {
            case .childManual: "statistics.sourceChild"
            case .parentApproval: "statistics.sourceApproval"
            case .parentCorrection: "parentToday.parentCorrection"
            }
        let timingKey: LocalizedStringKey =
            switch timing {
            case .beforeReminder: "statistics.autonomous"
            case .afterReminder: "statistics.afterReminder"
            case .unknown: "statistics.unknownTiming"
            }
        #expect(value.completionSourceKey == sourceKey && value.completionTimingKey == timingKey)
        #expect(!value.canManage && value.statusSymbol == "checkmark.circle.fill")
    }

    @Test("待验收行不会伪装未提交，不显示通用完成或跳过菜单")
    func waitingRowHasReviewStatusAndNoManagement() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let item = try query(fixture).item(id: occurrence.id, at: fixture.now)
        let presentation = ParentTodayTaskPresentation(item: item)
        #expect(item.status == .pending && presentation.statusKey == LocalizedStringKey("parentToday.statusWaiting"))
        #expect(presentation.statusSymbol == "hourglass" && !presentation.canManage)
        #expect(presentation.completionSourceKey == nil && presentation.completionTimingKey == nil)
    }

    @Test("行查询消费保存timing，不用后来提醒或来源回算", arguments: [-1.0, 0.0, 1.0])
    func actualCompletionQueryKeepsSavedTiming(offset: TimeInterval) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let row = try fixture.item(for: occurrence)
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: row.id, at: fixture.now.addingTimeInterval(2))
        occurrence.scheduledAt = fixture.now.addingTimeInterval(-600 + offset)
        try fixture.context.save()
        let item = try query(fixture).item(id: occurrence.id, at: fixture.now.addingTimeInterval(3))
        #expect(item.completion?.source == .parentApproval && item.completion?.timing == .beforeReminder)
        #expect(!fixture.context.hasChanges)
    }

    @Test("完整审计拒绝合法枚举但错误的保存自主性")
    func strictParentQueryRejectsChangedAudit() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: fixture.item(for: occurrence).id, at: fixture.now.addingTimeInterval(1))
        let record = try #require(occurrence.completionRecord)
        record.completionTimingRawValue = CompletionTiming.afterReminder.rawValue
        try fixture.context.save()
        #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(record.id)) {
            try query(fixture).item(id: occurrence.id, at: fixture.now.addingTimeInterval(2))
        }
    }

    @Test("孩子旧完成读取仍与无关坏账隔离，家长自主性读取严格拒绝")
    func childLegacyReadDoesNotGainAnUnrelatedLedgerDependency() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makePending(fixture)
        _ = try TaskProgressService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        let unrelatedID = UUID()
        fixture.context.insert(
            CoinTransaction(
                businessKey: RewardLedgerKey.coinReward(unrelatedID), sourceID: unrelatedID,
                kind: .reward, amount: 1, createdAt: fixture.now))
        try fixture.context.save()
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let child = TodayTaskQueryService(
            context: fixture.context, calendar: .init(identifier: .gregorian), timeZone: zone)
        #expect(try child.item(id: occurrence.id, at: fixture.now).completion?.timing == .unknown)
        #expect(throws: RewardLedgerError.corruptLedger(RewardLedgerKey.coinReward(unrelatedID))) {
            try query(fixture).item(id: occurrence.id, at: fixture.now)
        }
        #expect(!fixture.context.hasChanges)
    }

    @Test("家长列表写入后的概况同步重读，不由View编排持久化")
    func parentManagementRefreshesInjectedOverview() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makePending(fixture)
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let service = GrowthStatisticsQueryService(
            context: fixture.context, calendar: .init(identifier: .gregorian), timeZone: zone)
        let overview = ParentTodayOverviewViewModel(service: service, now: { fixture.now })
        let model = ParentTodayTaskViewModel(
            context: fixture.context, calendar: .init(identifier: .gregorian), timeZone: zone,
            dateProvider: FixedDateProvider(value: fixture.now), overviewModel: overview)
        #expect(overview.state == .idle)
        model.load()
        #expect(try counts(overview).eligible == 1 && counts(overview).completionRate == 0)
        model.skip(occurrenceID: occurrence.id)
        #expect(
            try counts(overview).eligible == 0 && counts(overview).skipped == 1
                && counts(overview).completionRate == nil)
        model.restore(occurrenceID: occurrence.id)
        #expect(try counts(overview).eligible == 1 && counts(overview).skipped == 0)
        #expect(!fixture.context.hasChanges && !model.isActionErrorPresented)
    }

    @Test("读取边界失败撤下已显示内容，同进程重试不改数据")
    func injectedReadFailureRemovesContentAndRetrySucceeds() throws {
        let fixture = try ParentReviewFixture()
        _ = try makePending(fixture)
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        var readCount = 0
        let service = GrowthStatisticsQueryService(
            context: fixture.context, calendar: .init(identifier: .gregorian), timeZone: zone,
            fetchOccurrences: { descriptor in
                readCount += 1
                if readCount == 2 { throw NSError(domain: "SyntheticStatisticsRead", code: 1) }
                return try fixture.context.fetch(descriptor)
            })
        let model = GrowthStatisticsViewModel(service: service, now: { fixture.now })
        model.load()
        guard case let .loaded(first) = model.state else { throw NSError(domain: "SyntheticStatisticsState", code: 1) }
        model.load()
        #expect(model.state == .failed)
        model.load()
        #expect(model.state == .loaded(first) && !fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
    }

    #if DEBUG
        @Test("UI失败工厂必须显式隔离授权，且只失败一次", arguments: [false, true])
        func debugReadFailureRequiresBothFlags(enabled: Bool) throws {
            let fixture = try ParentReviewFixture()
            _ = try makePending(fixture)
            let service = UITestStatisticsServiceFactory.make(
                context: fixture.context, calendar: .init(identifier: .gregorian),
                timeZone: try #require(TimeZone(secondsFromGMT: 0)),
                arguments: [UITestStatisticsServiceFactory.failureArgument]
                    + (enabled ? [UITestLaunchConfiguration.enableArgument] : []))
            if enabled {
                #expect(throws: NSError.self) { try service.snapshot(period: .week, at: fixture.now) }
            } else {
                #expect(try service.snapshot(period: .week, at: fixture.now).counts.eligible == 1)
            }
            #expect(
                try service.snapshot(period: .week, at: fixture.now).counts.eligible == 1 && !fixture.context.hasChanges
            )
        }
    #endif

    private func query(_ fixture: ParentReviewFixture) throws -> TodayTaskQueryService {
        TodayTaskQueryService(
            context: fixture.context, calendar: .init(identifier: .gregorian),
            timeZone: try #require(TimeZone(secondsFromGMT: 0)), validatesCompletionAudit: true)
    }

    private func makePending(_ fixture: ParentReviewFixture) throws -> TaskOccurrence {
        let occurrence = TaskOccurrence(
            templateID: UUID(), date: try LocalDate(dateKey: "2026-09-23"), scheduledAt: fixture.now,
            titleSnapshot: "合成管理统计", iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            sourceRevision: 1, createdAt: fixture.now, updatedAt: fixture.now)
        fixture.context.insert(occurrence)
        try fixture.context.save()
        return occurrence
    }

    private func counts(_ model: ParentTodayOverviewViewModel) throws -> GrowthStatisticsCounts {
        guard case let .loaded(day) = model.state else { throw NSError(domain: "SyntheticOverview", code: 1) }
        return day.counts
    }
}
