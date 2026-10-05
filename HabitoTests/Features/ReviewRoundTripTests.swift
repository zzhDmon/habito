import Foundation
import SwiftData
import Testing
@testable import Habito

/// 两个页面模型跨真实磁盘重开协作；全部业务时刻固定，不等待计时器或读取家庭数据。
@MainActor
@Suite("孩子与家长两轮验收磁盘闭环")
struct ReviewRoundTripTests {
    @Test("计时提交、退回重开、继续重提、次日通过和重复重开只有一次结算", arguments: [false, true])
    func timedRoundTripPersistsOriginalAuditAndOneReward(zero: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let first = try submitAndReturn(at: url, zero: zero)
        let secondID = try resubmitAndApprove(at: url, first: first, zero: zero)
        for _ in 0..<2 {
            try verifyFinalReopen(at: url, first: first, secondID: secondID, zero: zero)
        }
    }

    private func submitAndReturn(at url: URL, zero: Bool) throws -> ParentReviewQueueItem {
        let context = try makeContext(at: url)
        let now = try fixedNow()
        let occurrence = TaskOccurrence(
            id: V0MigrationFixture.pendingID, templateID: V0MigrationFixture.templateID,
            date: try LocalDate(dateKey: "2026-09-23"), scheduledAt: now.addingTimeInterval(120),
            titleSnapshot: "合成两轮审核", iconSnapshot: "book.fill", colorSnapshot: "reading",
            targetDurationSnapshot: 900, sourceRevision: 1,
            createdAt: now.addingTimeInterval(-120), updatedAt: now.addingTimeInterval(-120),
            verificationTypeSnapshot: .parentApproval, xpRewardSnapshot: zero ? 0 : 11,
            coinRewardSnapshot: zero ? 0 : 7, activeBonusCoinSnapshot: zero ? 0 : 3)
        context.insert(occurrence)
        try context.save()
        let trigger = NotificationRebuildTrigger()
        let started = try childModel(context: context, at: now.addingTimeInterval(-40), trigger: trigger)
        started.startOrResume()
        let paused = try childModel(context: context, at: now.addingTimeInterval(-10), trigger: trigger)
        paused.pause()
        let submitted = try childModel(context: context, at: now, trigger: trigger)
        submitted.completeTask()
        let waiting = try content(of: submitted)
        #expect(waiting.isAwaitingReview && waiting.activeDurationAtSnapshot == 30)
        let item = try #require(ParentReviewQueueService(context: context).items().first)
        #expect(item.id == submitted.completionFeedback?.id && item.activeDurationSeconds == 30)
        let parent = parentModel(context: context, at: now.addingTimeInterval(10), trigger: trigger)
        parent.returnForRevision(item)
        #expect(parent.feedback?.result.state == .returned && !parent.isActionErrorPresented)
        submitted.refresh()
        #expect(try content(of: submitted).submission?.state == .returned)
        #expect(try content(of: submitted).activeDurationAtSnapshot == 30)
        #expect(submitted.completionFeedback == nil && occurrence.id == item.occurrenceID)
        #expect(trigger.revision == 3)
        #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        return item
    }

    private func resubmitAndApprove(at url: URL, first: ParentReviewQueueItem, zero: Bool) throws -> UUID {
        // 上一阶段模型已离开作用域；重新创建容器，不能用内存对象冒充重启恢复。
        let context = try makeContext(at: url)
        let now = try fixedNow()
        let trigger = NotificationRebuildTrigger()
        let continued = try childModel(context: context, at: now.addingTimeInterval(20), trigger: trigger)
        #expect(try content(of: continued).submission?.id == first.id)
        #expect(try content(of: continued).activeDurationAtSnapshot == 30 && continued.completionFeedback == nil)
        continued.startOrResume()
        let paused = try childModel(context: context, at: now.addingTimeInterval(40), trigger: trigger)
        paused.pause()
        let submitted = try childModel(context: context, at: now.addingTimeInterval(50), trigger: trigger)
        submitted.completeTask()
        let second = try #require(ParentReviewQueueService(context: context).items().first)
        #expect(second.id != first.id && second.occurrenceID == first.occurrenceID)
        #expect(second.activeDurationSeconds == 50 && second.submittedAt == now.addingTimeInterval(50))
        #expect(second.reminderAt == first.reminderAt && second.timing == .beforeReminder)
        #expect(second.expectedXP == (zero ? 0 : 11) && second.expectedCoins == (zero ? 0 : 10))
        #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        let parent = parentModel(context: context, at: now.addingTimeInterval(86400), trigger: trigger)
        parent.approve(first)
        #expect(parent.actionFailure == .changedSubmission && trigger.revision == 2)
        #expect(try ParentReviewQueueService(context: context).items().first?.id == second.id)
        parent.prepareForPresentation()
        parent.approve(second)
        #expect(!parent.isActionErrorPresented && parent.feedback?.result.didReview == true)
        #expect(parent.feedback?.result.xp == (zero ? 0 : 11) && parent.feedback?.result.coins == (zero ? 0 : 10))
        #expect(trigger.revision == 3)
        parent.dismissFeedback()
        parent.approve(second)
        #expect(parent.feedback == nil && trigger.revision == 3)
        let completed = try childModel(context: context, at: now.addingTimeInterval(86400), trigger: trigger)
        let finalContent = try content(of: completed)
        #expect(finalContent.completion?.completedAt == second.submittedAt)
        #expect(finalContent.completion?.activeDurationSeconds == 50 && completed.completionFeedback == nil)
        #expect(finalContent.task.status == .completed && finalContent.primaryAction == .none)
        return second.id
    }

    private func verifyFinalReopen(at url: URL, first: ParentReviewQueueItem, secondID: UUID, zero: Bool) throws {
        let context = try makeContext(at: url)
        let now = try fixedNow().addingTimeInterval(86400)
        let trigger = NotificationRebuildTrigger()
        let parent = parentModel(context: context, at: now, trigger: trigger)
        #expect(parent.feedback == nil && !parent.isActionErrorPresented)
        #expect(try ParentReviewQueueService(context: context).items().isEmpty)
        let child = try childModel(context: context, at: now, trigger: trigger)
        #expect(try content(of: child).completion?.activeDurationSeconds == 50)
        #expect(child.completionFeedback == nil && trigger.revision == 0)
        let rows = try context.fetch(FetchDescriptor<TaskSubmission>()).sorted { $0.sequenceNumber < $1.sequenceNumber }
        #expect(rows.count == 2)
        let returned = try #require(rows.first)
        let approved = try #require(rows.last)
        #expect(returned.id == first.id && returned.reviewState == .returned && returned.activeDurationSeconds == 30)
        #expect(approved.id == secondID && approved.reviewState == .approved && approved.activeDurationSeconds == 50)
        #expect(approved.reminderAtSnapshot == first.reminderAt && approved.reviewedAt == now)
        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TimerSession>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        // 零金额也保留一对结算审计用于幂等，不能把“没发币”误断言为“没有账本事件”。
        let xpRows = try context.fetch(FetchDescriptor<XPTransaction>())
        let coinRows = try context.fetch(FetchDescriptor<CoinTransaction>())
        #expect(xpRows.count == 1 && coinRows.count == 1)
        let xp = try #require(xpRows.first)
        let coin = try #require(coinRows.first)
        #expect(xp.kind == .reward && coin.kind == .reward)
        #expect(xp.sourceID == approved.reviewedCompletionID && coin.sourceID == approved.reviewedCompletionID)
        #expect(xp.amount == (zero ? 0 : 11) && coin.amount == (zero ? 0 : 10))
        #expect(xp.createdAt == now && coin.createdAt == now)
        #expect(
            try RewardLedgerService(context: context).balance()
                == RewardBalance(effectiveXP: zero ? 0 : 11, coins: zero ? 0 : 10))
    }

    private func fixedNow() throws -> Date {
        try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
    }

    private func makeContext(at url: URL) throws -> ModelContext {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        return context
    }

    private func childModel(context: ModelContext, at now: Date, trigger: NotificationRebuildTrigger) throws
        -> TaskSessionViewModel
    {
        let model = TaskSessionViewModelFactory(
            context: context, calendar: Calendar(identifier: .gregorian),
            timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")),
            dateProvider: FixedDateProvider(value: now), notificationRebuildTrigger: trigger
        ).makeModel(for: V0MigrationFixture.pendingID)
        model.load()
        return model
    }

    private func parentModel(context: ModelContext, at now: Date, trigger: NotificationRebuildTrigger)
        -> ParentReviewViewModel
    {
        let model = ParentReviewViewModel(
            context: context, dateProvider: FixedDateProvider(value: now), notificationRebuildTrigger: trigger)
        model.prepareForPresentation()
        return model
    }

    private func content(of model: TaskSessionViewModel) throws -> TaskSessionScreenContent {
        guard case let .loaded(content) = model.state else { throw CocoaError(.coderInvalidValue) }
        return content
    }
}
