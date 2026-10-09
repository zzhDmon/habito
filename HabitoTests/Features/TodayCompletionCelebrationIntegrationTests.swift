import Foundation
import SwiftData
import Testing
@testable import Habito

/// 通过真实合成事务与工厂验证接线，不读取正式家庭库、网络或真实当前时间。
@Suite("今日仪式真实事务接线")
@MainActor
struct TodayCompletionCelebrationIntegrationTests {
    @Test("通关后新增今日任务撤下旧仪式，再确认仅结算新任务一次")
    func addingTodayTaskAfterCompletionReopensAndCelebratesAgain() throws {
        let fixture = try TodayQueryFixture()
        let first = try pending(fixture)
        let model = today(fixture)
        let sessionFactory = factory(fixture, saved: { model.receive(completion: $0) })
        let firstSession = sessionFactory.makeModel(for: first.id)
        firstSession.load()
        firstSession.completeTask()
        let firstEvent = try #require(model.celebrationModel.event)
        let originalBalance = try RewardLedgerService(context: fixture.context).balance()
        let added = try pending(fixture)
        model.load()
        #expect(model.celebrationModel.event == nil)
        let reopened = try fixture.snapshot()
        #expect(!reopened.isAllCompleted && reopened.totalCount == 2 && reopened.completedCount == 1)
        #expect(try RewardLedgerService(context: fixture.context).balance() == originalBalance)
        let addedSession = sessionFactory.makeModel(for: added.id)
        addedSession.load()
        addedSession.completeTask()
        let secondEvent = try #require(model.celebrationModel.event)
        #expect(secondEvent.id != firstEvent.id && secondEvent.completedCount == 2)
        #expect(try fixture.snapshot().isAllCompleted)
        addedSession.completeTask()
        model.load()
        #expect(model.celebrationModel.event == secondEvent)
        #expect(
            try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 22, coins: 20))
        try expectTransactions(fixture.context, count: 2)
    }

    @Test("通关后只新增未来任务不改变今日资格或奖励")
    func addingFutureTaskPreservesTodayCompletion() throws {
        let fixture = try TodayQueryFixture()
        let first = try pending(fixture)
        let model = today(fixture)
        let session = factory(fixture, saved: { model.receive(completion: $0) }).makeModel(for: first.id)
        session.load()
        session.completeTask()
        let event = try #require(model.celebrationModel.event)
        _ = fixture.makeOccurrence(
            title: "明天的新增任务", scheduledAt: fixture.now.addingTimeInterval(86400), status: .pending,
            date: try LocalDate(dateKey: "2026-09-24"))
        try fixture.context.save()
        model.load()
        #expect(model.celebrationModel.event == event)
        #expect(try fixture.snapshot().isAllCompleted)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("构造和无事件历史加载不读取附加资格，也不补播历史")
    func historicalLoadDoesNotReadOrCreateNewEvent() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        _ = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        var reads = 0
        let model = today(
            fixture,
            read: {
                reads += 1
                throw NSError(domain: "HabitoSyntheticUnexpectedRead", code: 1)
            })
        #expect(reads == 0)
        for _ in 0..<3 { model.load() }
        #expect(reads == 0 && model.celebrationModel.event == nil && !model.celebrationVerificationFailed)
        #expect(!fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("真实自行确认保存后工厂回调一次，零奖励也有稳定仪式", arguments: [false, true])
    func savedCompletionPublishesOnceThroughFactory(zero: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture, zero: zero)
        let model = today(fixture)
        var receipts: [TaskCompletionResult] = []
        var contextWasClean = true
        let factory = factory(
            fixture,
            saved: {
                contextWasClean = contextWasClean && !fixture.context.hasChanges
                receipts.append($0)
                model.receive(completion: $0)
            }, changed: model.refreshCelebration)
        let first = factory.makeModel(for: occurrence.id)
        let stale = factory.makeModel(for: occurrence.id)
        first.load()
        stale.load()
        first.completeTask()
        let event = try #require(model.celebrationModel.event)
        #expect(event.id == occurrence.completionRecord?.id && event.completedCount == 1)
        #expect(receipts.count == 1 && contextWasClean && !model.celebrationVerificationFailed)
        #expect(receipts.first?.xp == (zero ? 0 : 11) && receipts.first?.coins == (zero ? 0 : 10))
        #expect(model.celebrationModel.claimAnimation(eventID: event.id))
        first.completeTask()
        stale.completeTask()
        first.dismissCompletionFeedback()
        model.load()
        #expect(receipts.count == 1 && model.celebrationModel.event == event)
        #expect(!model.celebrationModel.claimAnimation(eventID: event.id))
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("较早完成只消费ID，真正最后一项才生成当天事件")
    func onlyLastConfirmationCreatesEvent() throws {
        let fixture = try TodayQueryFixture()
        let first = try pending(fixture)
        let second = try pending(fixture)
        let model = today(fixture)
        let factory = factory(fixture, saved: { model.receive(completion: $0) })
        let firstSession = factory.makeModel(for: first.id)
        firstSession.load()
        firstSession.completeTask()
        #expect(model.celebrationModel.event == nil)
        let secondSession = factory.makeModel(for: second.id)
        secondSession.load()
        secondSession.completeTask()
        #expect(model.celebrationModel.event?.id == second.completionRecord?.id)
        #expect(model.celebrationModel.event?.completedCount == 2)
        try expectTransactions(fixture.context, count: 2)
    }

    @Test("待验收提交不走确认回调，不生成仪式或奖励")
    func submissionDoesNotPublishCompletion() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        let model = today(fixture)
        var calls = 0
        let session = factory(
            fixture,
            saved: {
                calls += 1
                model.receive(completion: $0)
            }
        ).makeModel(for: occurrence.id)
        session.load()
        session.completeTask()
        #expect(calls == 0 && occurrence.status == .pending && model.celebrationModel.event == nil)
        #expect(try TaskSubmissionHistory(context: fixture.context).latest(for: occurrence)?.reviewState == .waiting)
        try expectTransactions(fixture.context, count: 0)
    }

    @Test("真实撤销刷新撤下旧事件，重新完成新ID才能再获资格")
    func savedUndoInvalidatesWithoutPublishingNewEvent() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        let model = today(fixture)
        var changes = 0
        let session = factory(
            fixture, saved: { model.receive(completion: $0) },
            changed: {
                changes += 1
                model.refreshCelebration()
            }
        ).makeModel(for: occurrence.id)
        session.load()
        session.completeTask()
        let original = try #require(model.celebrationModel.event)
        session.undoCompletion()
        #expect(changes == 1 && model.celebrationModel.event == nil && occurrence.status == .pending)
        session.completeTask()
        let latest = try #require(model.celebrationModel.event)
        #expect(latest.id != original.id && latest.id == occurrence.completionRecord?.id)
        model.celebrationModel.dismiss(eventID: original.id)
        #expect(model.celebrationModel.event == latest)
        try expectTransactions(fixture.context, count: 3)
    }

    @Test("自行确认保存失败不投递，真实重试成功才投递一次")
    func failedCompletionSaveDoesNotPublishEvent() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        let model = today(fixture)
        var calls = 0
        let failing = TaskSessionViewModelFactory(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now),
            completionService: TaskCompletionService(
                context: fixture.context,
                saveChanges: {
                    _ in throw NSError(domain: "HabitoSyntheticCompletionSave", code: 1)
                }),
            onCompletionSaved: {
                calls += 1
                model.receive(completion: $0)
            }
        ).makeModel(for: occurrence.id)
        failing.load()
        failing.completeTask()
        #expect(calls == 0 && model.celebrationModel.event == nil && failing.completionFeedback == nil)
        #expect(failing.actionFailure == .saveFailed && occurrence.status == .pending && !fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 0)
        let retry = factory(
            fixture,
            saved: {
                calls += 1
                model.receive(completion: $0)
            }
        ).makeModel(for: occurrence.id)
        retry.load()
        retry.completeTask()
        #expect(calls == 1 && model.celebrationModel.event?.id == occurrence.completionRecord?.id)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("新通过回调绑定真实审核ID，旧并行页面不能重复投递", arguments: [false, true])
    func savedApprovalPublishesOnce(zero: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting(zero: zero)
        let model = try parentToday(fixture)
        var receipts: [TaskSubmissionReviewResult] = []
        let callback: @MainActor (TaskSubmissionReviewResult) -> Void = {
            #expect(!fixture.context.hasChanges)
            receipts.append($0)
            model.receive(review: $0)
        }
        let first = ParentReviewViewModel(
            context: fixture.context, dateProvider: FixedDateProvider(value: fixture.now), onApprovalSaved: callback)
        let stale = ParentReviewViewModel(
            context: fixture.context, dateProvider: FixedDateProvider(value: fixture.now), onApprovalSaved: callback)
        first.load()
        stale.load()
        let item = try fixture.item(for: occurrence)
        first.approve(item)
        let event = try #require(model.celebrationModel.event)
        #expect(event.id == occurrence.completionRecord?.id && event.id == receipts.first?.completionID)
        #expect(receipts.first?.submissionID == item.id && !model.celebrationVerificationFailed)
        stale.approve(item)
        first.approve(item)
        model.load()
        #expect(receipts.count == 1 && model.celebrationModel.event == event)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("退回或审核保存失败都不发布，之后成功重试才投递", arguments: [false, true])
    func returnOrFailedReviewDoesNotPublish(failSave: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let model = try parentToday(fixture)
        var calls = 0
        let review = ParentReviewViewModel(
            context: fixture.context, dateProvider: FixedDateProvider(value: fixture.now),
            reviewService: TaskSubmissionReviewService(
                context: fixture.context,
                saveChanges: { context in
                    if failSave { throw NSError(domain: "HabitoSyntheticReviewSave", code: 1) }
                    try context.save()
                }),
            onApprovalSaved: {
                calls += 1
                model.receive(review: $0)
            })
        review.load()
        let item = try fixture.item(for: occurrence)
        if failSave { review.approve(item) } else { review.returnForRevision(item) }
        #expect(calls == 0 && model.celebrationModel.event == nil)
        #expect(occurrence.status == .pending && !fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 0)
        if failSave {
            #expect(review.actionFailure == .saveFailed)
            let retry = ParentReviewViewModel(
                context: fixture.context, dateProvider: FixedDateProvider(value: fixture.now),
                onApprovalSaved: {
                    calls += 1
                    model.receive(review: $0)
                })
            retry.load()
            retry.approve(item)
            #expect(calls == 1 && model.celebrationModel.event?.id == occurrence.completionRecord?.id)
        }
    }

    @Test("额外资格读取失败不改变真实保存成功，恢复只撤错不补播")
    func qualificationFailureDoesNotTurnCompletionIntoSaveFailure() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        var shouldFail = true
        let query = TodayTaskQueryService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            validatesCompletionAudit: true)
        let model = today(
            fixture,
            read: {
                if shouldFail { throw NSError(domain: "HabitoSyntheticQualificationRead", code: 1) }
                return try query.snapshot(for: fixture.date, at: fixture.now)
            })
        let session = factory(fixture, saved: { model.receive(completion: $0) }).makeModel(for: occurrence.id)
        session.load()
        session.completeTask()
        #expect(occurrence.status == .completed && session.actionFailure == nil)
        #expect(
            session.completionFeedback != nil && model.celebrationVerificationFailed
                && model.celebrationModel.event == nil)
        #expect(
            try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
        shouldFail = false
        model.load()
        #expect(!model.celebrationVerificationFailed && model.celebrationModel.event == nil)
        guard case let .completed(receipt) = session.completionFeedback else {
            Issue.record("辅助失败后必须仍保留真实完成收据"); return
        }
        model.receive(completion: receipt)
        #expect(model.celebrationModel.event == nil)
        #expect(!fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("合法枚举但坏审计撤下仪式，普通任务与真实资产仍可读取")
    func auditFailureStaysSeparateFromNormalTodayQuery() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        let model = today(fixture)
        let session = factory(fixture, saved: { model.receive(completion: $0) }).makeModel(for: occurrence.id)
        session.load()
        session.completeTask()
        let record = try #require(occurrence.completionRecord)
        #expect(model.celebrationModel.event != nil)
        record.completionTimingRawValue = CompletionTiming.afterReminder.rawValue
        try fixture.context.save()
        model.load()
        #expect(model.celebrationVerificationFailed && model.celebrationModel.event == nil)
        guard case let .loaded(content) = model.state, case let .loaded(balance) = model.rewardState else {
            Issue.record("附加完整审计失败不能阻断原任务/资产读取"); return
        }
        #expect(content.completedCount == 1 && balance == RewardBalance(effectiveXP: 11, coins: 10))
        record.completionTimingRawValue = CompletionTiming.beforeReminder.rawValue
        try fixture.context.save()
        model.refreshCelebration()
        #expect(!model.celebrationVerificationFailed && model.celebrationModel.event == nil)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("未保存草稿不能成为仪式事实，失败不保存或回滚用户编辑")
    func dirtyContextRejectsQualificationWithoutChangingDraft() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        let model = today(fixture)
        let session = factory(fixture, saved: { model.receive(completion: $0) }).makeModel(for: occurrence.id)
        session.load()
        session.completeTask()
        occurrence.titleSnapshot = "合成未保存草稿"
        model.refreshCelebration()
        #expect(model.celebrationVerificationFailed && model.celebrationModel.event == nil)
        #expect(fixture.context.hasChanges && occurrence.titleSnapshot == "合成未保存草稿")
        try expectTransactions(fixture.context, count: 1)
        try fixture.context.save()
        model.refreshCelebration()
        #expect(!model.celebrationVerificationFailed && model.celebrationModel.event == nil)
    }

    @Test("跨日加载使已有事件失效，旧日新完成也不能触发今日仪式")
    func nextDayAndHistoricalCompletionCannotCelebrateToday() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        let model = today(fixture)
        let session = factory(fixture, saved: { model.receive(completion: $0) }).makeModel(for: occurrence.id)
        session.load()
        session.completeTask()
        let nextDay = TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now.addingTimeInterval(86400)),
            celebrationModel: model.celebrationModel)
        nextDay.load()
        #expect(model.celebrationModel.event == nil && !nextDay.celebrationVerificationFailed)
        let oldTask = try pending(fixture)
        let oldSession = factory(fixture, saved: { nextDay.receive(completion: $0) }).makeModel(for: oldTask.id)
        oldSession.load()
        oldSession.completeTask()
        #expect(oldTask.status == .completed && nextDay.celebrationModel.event == nil)
        try expectTransactions(fixture.context, count: 2)
    }

    @Test("普通任务查询损坏时已有事件撤下，修复加载不补播")
    func normalTodayFailureAlsoWithdrawsEvent() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = try pending(fixture)
        let model = today(fixture)
        let session = factory(fixture, saved: { model.receive(completion: $0) }).makeModel(for: occurrence.id)
        session.load()
        session.completeTask()
        occurrence.statusRawValue = "synthetic-invalid"
        try fixture.context.save()
        model.load()
        #expect(model.state == .failed && model.celebrationModel.event == nil)
        occurrence.statusRawValue = TaskOccurrenceStatus.completed.rawValue
        try fixture.context.save()
        model.load()
        #expect(model.celebrationModel.event == nil)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("审核额外校验失败仍保存通过，恢复重传同结果不补播")
    func qualificationFailureAlsoConsumesApprovalIdentity() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let query = TodayTaskQueryService(
            context: fixture.context, calendar: calendar, timeZone: timeZone, validatesCompletionAudit: true)
        let date = try LocalDate(date: fixture.now, calendar: calendar, timeZone: timeZone)
        var shouldFail = true
        let model = TodayViewModel(
            context: fixture.context, calendar: calendar, timeZone: timeZone,
            dateProvider: FixedDateProvider(value: fixture.now),
            readCelebrationSnapshot: {
                if shouldFail { throw NSError(domain: "HabitoSyntheticApprovalQualificationRead", code: 1) }
                return try query.snapshot(for: date, at: fixture.now)
            })
        var saved: TaskSubmissionReviewResult?
        let review = ParentReviewViewModel(
            context: fixture.context, dateProvider: FixedDateProvider(value: fixture.now),
            onApprovalSaved: {
                saved = $0
                model.receive(review: $0)
            })
        review.load()
        review.approve(try fixture.item(for: occurrence))
        #expect(occurrence.status == .completed && review.feedback != nil && review.actionFailure == nil)
        #expect(model.celebrationVerificationFailed && model.celebrationModel.event == nil)
        shouldFail = false
        model.refreshCelebration()
        model.receive(review: try #require(saved))
        #expect(!model.celebrationVerificationFailed && model.celebrationModel.event == nil)
        #expect(!fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 1)
    }

    private func pending(_ fixture: TodayQueryFixture, zero: Bool = false) throws -> TaskOccurrence {
        let occurrence = fixture.makeOccurrence(
            title: "合成固定任务", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.xpRewardSnapshot = zero ? 0 : 11
        occurrence.coinRewardSnapshot = zero ? 0 : 7
        occurrence.activeBonusCoinSnapshot = zero ? 0 : 3
        try fixture.context.save()
        return occurrence
    }

    private func today(_ fixture: TodayQueryFixture, read: (() throws -> TodayTasksSnapshot)? = nil)
        -> TodayViewModel
    {
        TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now), readCelebrationSnapshot: read)
    }

    private func parentToday(_ fixture: ParentReviewFixture) throws -> TodayViewModel {
        TodayViewModel(
            context: fixture.context, calendar: Calendar(identifier: .gregorian),
            timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")),
            dateProvider: FixedDateProvider(value: fixture.now))
    }

    private func factory(
        _ fixture: TodayQueryFixture, saved: (@MainActor (TaskCompletionResult) -> Void)? = nil,
        changed: (@MainActor () -> Void)? = nil
    ) -> TaskSessionViewModelFactory {
        TaskSessionViewModelFactory(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now), onCompletionSaved: saved, onCompletionChanged: changed)
    }

    private func expectTransactions(_ context: ModelContext, count: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == count)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == count)
    }
}
