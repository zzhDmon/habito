import Foundation
import SwiftData
import Testing
@testable import Habito

/// 统计只在合成内存/磁盘库读取；真实事务先保存，固定时钟使测试不依赖设备日期。
@MainActor
struct GrowthStatisticsQueryServiceTests {
    @Test("真实自行确认消费保存自主性，不按后来修改的提醒推算", arguments: [-1.0, 0.0, 1.0])
    func selfConfirmationUsesSavedTiming(offset: TimeInterval) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        _ = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now.addingTimeInterval(offset), source: .childManual)
        occurrence.scheduledAt = fixture.now.addingTimeInterval(-600)
        try fixture.context.save()
        let result = try query(fixture, at: fixture.now.addingTimeInterval(2))
        #expect(result.counts.completed == 1 && result.counts.knownTiming == 1)
        #expect(result.counts.autonomous == (offset < 0 ? 1 : 0))
        #expect(result.counts.childConfirmed == 1 && !fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("次日审核和零奖励仍按原实例日期及提交自主性统计", arguments: [false, true])
    func lateApprovalStaysOnOriginalOccurrenceDay(zero: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting(day: "2026-09-22", zero: zero)
        let row = try fixture.item(for: occurrence)
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: row.id, at: fixture.now.addingTimeInterval(86_400))
        occurrence.scheduledAt = fixture.now.addingTimeInterval(-600)
        try fixture.context.save()
        let result = try query(fixture, at: fixture.now.addingTimeInterval(86_401))
        #expect(result.end.dateKey == "2026-09-24" && result.counts.parentApproved == 1)
        #expect(result.counts.autonomyRate == 1 && result.counts.knownTiming == 1)
        #expect(result.days.first { $0.date.dateKey == "2026-09-22" }?.counts.completed == 1)
        #expect(result.days.last?.counts.eligible == 0)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("等待和退回均未完成，重提后通过只计一个实例")
    func reviewRoundTripKeepsOneDenominator() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let review = TaskSubmissionReviewService(context: fixture.context)
        let first = try fixture.item(for: occurrence)
        let waiting = try query(fixture)
        #expect(waiting.counts.eligible == 1 && waiting.counts.awaitingReview == 1)
        #expect(waiting.counts.completionRate == 0 && waiting.counts.autonomyRate == nil)
        _ = try review.returnForRevision(
            occurrence, submissionID: first.id, at: fixture.now.addingTimeInterval(1))
        let returned = try query(fixture, at: fixture.now.addingTimeInterval(1))
        #expect(returned.counts.completed == 0 && returned.counts.awaitingReview == 0)
        _ = try TaskSubmissionService(context: fixture.context).submit(
            occurrence, at: fixture.now.addingTimeInterval(2))
        let second = try fixture.item(for: occurrence)
        #expect(second.id != first.id)
        _ = try review.approve(occurrence, submissionID: second.id, at: fixture.now.addingTimeInterval(3))
        let approved = try query(fixture, at: fixture.now.addingTimeInterval(4))
        #expect(approved.counts.eligible == 1 && approved.counts.completed == 1)
        #expect(approved.counts.awaitingReview == 0 && approved.counts.parentApproved == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 2)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("撤销保留历史，但当前完成率回落；再次完成不叠加旧分子")
    func undoAndRecompletionUseOnlyEffectiveFact() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        let first = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now.addingTimeInterval(-1), source: .childManual)
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: first.completionID, at: fixture.now.addingTimeInterval(1))
        let undone = try query(fixture, at: fixture.now.addingTimeInterval(1))
        #expect(undone.counts.eligible == 1 && undone.counts.completed == 0 && undone.counts.autonomyRate == nil)
        _ = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now.addingTimeInterval(2), source: .parentCorrection)
        let redone = try query(fixture, at: fixture.now.addingTimeInterval(3))
        #expect(redone.counts.completed == 1 && redone.counts.knownTiming == 1)
        #expect(redone.counts.autonomyRate == 0 && redone.counts.parentCorrected == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 2)
        try expectTransactions(fixture.context, count: 3)
    }

    @Test("旧unknown保留完成但排除自主分母；跳过和缺失日期不造分母")
    func legacyUnknownAndSkippedRemainDistinct() throws {
        let fixture = try ParentReviewFixture()
        let old = try makeOccurrence(fixture)
        _ = try TaskProgressService(context: fixture.context).complete(old, at: fixture.now, source: .childManual)
        _ = try makeOccurrence(fixture, status: .skipped)
        _ = try makeOccurrence(fixture)
        let result = try query(fixture)
        #expect(result.counts.eligible == 2 && result.counts.completed == 1 && result.counts.skipped == 1)
        #expect(result.counts.completionRate == 0.5 && result.counts.autonomyRate == nil)
        #expect(result.counts.unknownTiming == 1)
        #expect(result.days.dropLast().allSatisfy { $0.counts.eligible == 0 && $0.counts.completionRate == nil })
        #expect(
            old.completionRecord?.completionTiming == .unknown && old.completionRecord?.rewardSettlementVersion == 0)
        try expectTransactions(fixture.context, count: 0)
    }

    @Test("同一绝对时刻由显式业务时区决定今天和未来排除", arguments: ["Asia/Shanghai", "America/Los_Angeles"])
    func injectedTimeZoneDefinesToday(identifier: String) throws {
        let fixture = try ParentReviewFixture()
        _ = try makeOccurrence(fixture, date: "2026-09-22")
        _ = try makeOccurrence(fixture, date: "2026-09-23")
        let timeZone = try #require(TimeZone(identifier: identifier))
        let result = try service(fixture, timeZone: timeZone).snapshot(period: .week, at: fixture.now)
        let isShanghai = identifier == "Asia/Shanghai"
        #expect(result.end.dateKey == (isShanghai ? "2026-09-23" : "2026-09-22"))
        #expect(result.counts.eligible == (isShanghai ? 2 : 1))
        #expect(result.days.last?.counts.eligible == 1 && !fixture.context.hasChanges)
    }

    @Test("DST跳时真实查询仍按七个本地日期选择历史")
    func daylightSavingWindowUsesCivilDates() throws {
        let fixture = try ParentReviewFixture()
        let now = try V0MigrationFixture.instant("2026-03-08T10:30:00Z")
        _ = try makeOccurrence(fixture, date: "2026-03-02", reminder: now)
        _ = try makeOccurrence(fixture, date: "2026-03-01", reminder: now)
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let result = try service(fixture, timeZone: zone).snapshot(period: .week, at: now)
        #expect(result.start.dateKey == "2026-03-02" && result.end.dateKey == "2026-03-08")
        #expect(result.days.count == 7 && result.counts.eligible == 1)
    }

    @Test("脏编辑拒绝查询且不保存或回滚，显式保存后可重读")
    func pendingEditsArePreserved() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        occurrence.titleSnapshot = "未保存的新名称"
        #expect(throws: GrowthStatisticsQueryError.pendingContextChanges) { try query(fixture) }
        #expect(fixture.context.hasChanges && occurrence.titleSnapshot == "未保存的新名称")
        try fixture.context.save()
        #expect(try query(fixture).tasks.first?.title == "未保存的新名称")
        try expectTransactions(fixture.context, count: 0)
    }

    @Test("坏状态及无完成/计时的矛盾状态不能洗白成未完成", arguments: [0, 1, 2])
    func invalidStatusesAreExplicit(variant: Int) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        occurrence.statusRawValue = ["broken", "completed", "inProgress"][variant]
        try fixture.context.save()
        let expected: TodayTaskQueryError =
            switch variant {
            case 0: .invalidOccurrenceStatus(occurrenceID: occurrence.id, value: "broken")
            case 1: .missingCompletionRecord(occurrenceID: occurrence.id)
            default: .missingActiveSession(occurrenceID: occurrence.id)
            }
        #expect(throws: expected) { try query(fixture) }
        #expect(!fixture.context.hasChanges)
    }

    @Test("损坏绝对时间不是未设置时间")
    func invalidStoredOccurrenceTimeIsRejected() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        occurrence.plannedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        try fixture.context.save()
        #expect(throws: TodayTaskQueryError.invalidOccurrenceTime(occurrenceID: occurrence.id, field: "plannedAt")) {
            try query(fixture)
        }
    }

    @Test("断开的有效完成双向关系明确拒绝，不暗算完成")
    func brokenCompletionRelationIsRejected() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        let record = try TaskProgressService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        occurrence.completionRecord = nil
        record.occurrence = nil
        try fixture.context.save()
        #expect(throws: GrowthStatisticsQueryError.invalidCompletionRelation(occurrence.id)) { try query(fixture) }
    }

    @Test("坏完成自主性/非有限时刻不允许进入比例", arguments: [false, true])
    func invalidCompletionAuditIsRejected(time: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        let result = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        let record = try #require(occurrence.completionRecord)
        if time {
            record.completedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        } else {
            record.completionTimingRawValue = "broken"
        }
        try fixture.context.save()
        #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(result.completionID)) { try query(fixture) }
    }

    @Test("原奖励缺半边明确拒绝，不用完成状态掩盖坏账")
    func incompleteLedgerIsRejected() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        let result = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        let xp = try #require(fixture.context.fetch(FetchDescriptor<XPTransaction>()).first)
        fixture.context.delete(xp)
        try fixture.context.save()
        #expect(throws: RewardLedgerError.corruptLedger(RewardLedgerKey.coinReward(result.completionID))) {
            try query(fixture)
        }
        #expect(!fixture.context.hasChanges)
    }

    @Test("批准审计变化不能沿用旧比例")
    func changedReviewAuditIsRejected() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let row = try fixture.item(for: occurrence)
        let result = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: row.id, at: fixture.now.addingTimeInterval(1))
        let id = try #require(result.completionID)
        let submission = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        submission.reviewedAt = fixture.now.addingTimeInterval(2)
        try fixture.context.save()
        #expect(throws: TaskCompletionServiceError.invalidStoredCompletion(id)) {
            try query(fixture, at: fixture.now.addingTimeInterval(3))
        }
    }

    @Test("非法查询时刻与时钟倒退明确失败，不展示未来完成")
    func queryTimestampAndFutureCompletionAreRejected() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try makeOccurrence(fixture)
        let result = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        #expect(throws: GrowthStatisticsQueryError.invalidTimestamp) {
            try query(fixture, at: Date(timeIntervalSinceReferenceDate: .nan))
        }
        #expect(throws: GrowthStatisticsQueryError.completionAfterQueryTime(result.completionID)) {
            try query(fixture, at: fixture.now.addingTimeInterval(-1))
        }
    }

    @Test("磁盘多次重开统计一致，查询不增加交易/提交或修改已读")
    func diskReopenIsReadOnly() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let expected = try seedDisk(at: url)
        for _ in 0..<2 {
            let fixture = try ParentReviewFixture(storeURL: url)
            for _ in 0..<3 { #expect(try query(fixture, at: fixture.now.addingTimeInterval(2)) == expected) }
            #expect(!fixture.context.hasChanges)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 2)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 2)
            try expectTransactions(fixture.context, count: 2)
            #expect(
                try fixture.context.fetch(FetchDescriptor<CompletionRecord>()).allSatisfy {
                    $0.childFeedbackAcknowledgedAt == nil
                })
        }
    }

    @Test("冻结V0迁移后的unknown和放假单日恢复事实不被重写", arguments: [false, true])
    func frozenV0HistoryRemainsReadOnly(versioned: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V0MigrationFixture.seed(at: url, versioned: versioned)
        for _ in 0..<2 {
            let fixture = try ParentReviewFixture(storeURL: url)
            let result = try query(fixture)
            #expect(result.counts.eligible == 3 && result.counts.completed == 1)
            #expect(result.counts.unknownTiming == 1 && result.counts.autonomyRate == nil)
            // 放假免做的普通实例不会补造；家长显式单日恢复及受保护历史沿用已有优先级。
            #expect(result.days.first { $0.date.dateKey == "2026-09-22" }?.counts.eligible == 1)
            #expect(result.tasks.count == 1 && result.counts.completionRate == 1.0 / 3)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 4)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 2)
            #expect(!fixture.context.hasChanges)
            try expectTransactions(fixture.context, count: 0)
        }
    }

    @Test("冻结旧审核库迁移后仅计有效完成，审核和账本保持不补投递")
    func frozenReviewedHistoryRemainsReadOnly() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V5MigrationFixture.seed(at: url)
        let now = try V0MigrationFixture.instant("2026-09-24T12:00:00Z")
        for _ in 0..<2 {
            let fixture = try ParentReviewFixture(storeURL: url)
            let xpCount = try fixture.context.fetchCount(FetchDescriptor<XPTransaction>())
            let coinCount = try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>())
            let result = try query(fixture, at: now)
            #expect(result.counts.eligible == 3 && result.counts.completed == 1)
            #expect(result.counts.parentApproved == 1 && result.counts.awaitingReview == 1)
            #expect(result.counts.autonomyRate == 1 && result.counts.knownTiming == 1)
            #expect(result.days.first { $0.date.dateKey == "2026-09-22" }?.counts.completed == 1)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 2)
            #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 3)
            #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == xpCount)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == coinCount)
            #expect(
                try fixture.context.fetch(FetchDescriptor<CompletionRecord>()).allSatisfy {
                    $0.childFeedbackDeliveryVersion == 0 && $0.childFeedbackAcknowledgedAt == nil
                })
            #expect(!fixture.context.hasChanges)
        }
    }

    private func seedDisk(at url: URL) throws -> GrowthStatisticsSnapshot {
        let fixture = try ParentReviewFixture(storeURL: url)
        let child = try makeOccurrence(fixture, date: "2026-09-22")
        _ = try TaskCompletionService(context: fixture.context).complete(child, at: fixture.now, source: .childManual)
        let approved = try fixture.makeWaiting()
        let row = try fixture.item(for: approved)
        _ = try TaskSubmissionReviewService(context: fixture.context).approve(
            approved, submissionID: row.id, at: fixture.now.addingTimeInterval(1))
        _ = try fixture.makeWaiting(id: UUID(), day: "2026-09-21")
        return try query(fixture, at: fixture.now.addingTimeInterval(2))
    }

    private func service(_ fixture: ParentReviewFixture, timeZone: TimeZone? = nil) throws
        -> GrowthStatisticsQueryService
    {
        let zone = try #require(timeZone ?? TimeZone(secondsFromGMT: 0))
        return GrowthStatisticsQueryService(
            context: fixture.context, calendar: Calendar(identifier: .gregorian),
            timeZone: zone)
    }

    private func query(_ fixture: ParentReviewFixture, at now: Date? = nil) throws -> GrowthStatisticsSnapshot {
        try service(fixture).snapshot(period: .week, at: now ?? fixture.now)
    }

    private func makeOccurrence(
        _ fixture: ParentReviewFixture, date: String = "2026-09-23", status: TaskOccurrenceStatus = .pending,
        reminder: Date? = nil
    ) throws -> TaskOccurrence {
        let occurrence = TaskOccurrence(
            templateID: UUID(), date: try LocalDate(dateKey: date), scheduledAt: reminder ?? fixture.now,
            titleSnapshot: "合成统计任务", iconSnapshot: "book.fill", colorSnapshot: "reading",
            targetDurationSnapshot: 900, status: status, sourceRevision: 1,
            createdAt: fixture.now, updatedAt: fixture.now,
            xpRewardSnapshot: 11, coinRewardSnapshot: 7, activeBonusCoinSnapshot: 3)
        fixture.context.insert(occurrence)
        try fixture.context.save()
        return occurrence
    }

    private func expectTransactions(_ context: ModelContext, count: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == count)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == count)
    }
}
