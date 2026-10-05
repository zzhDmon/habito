import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("家长审核页面用例状态")
struct ParentReviewViewModelTests {
    @Test("次日真实通过刷新队列且仅发布一次收据通知，零奖励仍保留事实", arguments: [false, true])
    func approvalPublishesOnce(zero: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting(day: "2026-09-22", zero: zero)
        let trigger = NotificationRebuildTrigger()
        let model = fixture.model(at: fixture.now.addingTimeInterval(86400), trigger: trigger)
        model.load()
        let item = try #require(fixture.items(from: model).first)
        #expect(model.feedback == nil && item.occurrenceID == occurrence.id)
        model.approve(item)
        let receipt = try #require(model.feedback?.result)
        #expect(receipt.didReview && receipt.submissionID == item.id && receipt.state == .approved)
        #expect(receipt.xp == (zero ? 0 : 11) && receipt.coins == (zero ? 0 : 10))
        #expect(receipt.timing == .beforeReminder && receipt.reviewedAt == fixture.now.addingTimeInterval(86400))
        #expect(occurrence.completionRecord?.completedAt == fixture.now)
        #expect(try fixture.items(from: model).isEmpty && trigger.revision == 1 && !model.isActionErrorPresented)
        model.refresh()
        #expect(model.feedback?.result == receipt)
        model.dismissFeedback()
        model.approve(item)
        #expect(model.feedback == nil && trigger.revision == 1 && model.actionFailure == nil)
        let reentered = fixture.model()
        reentered.load()
        #expect(try fixture.items(from: reentered).isEmpty && reentered.feedback == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 1)
    }

    @Test("退回保留原计时不发奖，重提清空旧反馈且旧请求不审核新轮次")
    func returnedRequestNeverApprovesNewRound() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let trigger = NotificationRebuildTrigger()
        let model = fixture.model(trigger: trigger)
        model.load()
        let old = try #require(fixture.items(from: model).first)
        model.returnForRevision(old)
        #expect(model.feedback?.result.state == .returned && model.feedback?.result.coins == 0)
        #expect(trigger.revision == 1 && occurrence.timerSessions.first?.accumulatedActiveSeconds == 30)
        let next = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        model.refresh()
        let refreshedItems = try fixture.items(from: model)
        #expect(model.feedback == nil && refreshedItems.first?.id == next.submissionID)
        model.returnForRevision(old)
        #expect(model.feedback == nil && !model.isActionErrorPresented && trigger.revision == 1)
        model.approve(old)
        #expect(model.actionFailure == .changedSubmission && model.isActionErrorPresented)
        #expect((try fixture.items(from: model).first?.id) == next.submissionID && trigger.revision == 1)
        #expect(try TaskSubmissionHistory(context: fixture.context).latest(for: occurrence)?.reviewState == .waiting)
        try fixture.expectNoReward()
    }

    @Test("两页面捕获同一提交，第二页面重复不发事件，冲突操作明确报错", arguments: [false, true])
    func staleParallelPagesDoNotRepeat(approve: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let firstTrigger = NotificationRebuildTrigger()
        let secondTrigger = NotificationRebuildTrigger()
        let first = fixture.model(trigger: firstTrigger)
        let second = fixture.model(trigger: secondTrigger)
        first.load()
        second.load()
        let item = try #require(fixture.items(from: second).first)
        if approve {
            first.approve(item)
            second.approve(item)
        } else {
            first.returnForRevision(item)
            second.returnForRevision(item)
        }
        #expect(firstTrigger.revision == 1 && secondTrigger.revision == 0 && second.feedback == nil)
        #expect(try fixture.items(from: second).isEmpty && !second.isActionErrorPresented)
        if approve { second.returnForRevision(item) } else { second.approve(item) }
        #expect(second.actionFailure == .changedSubmission && second.isActionErrorPresented)
        #expect(occurrence.status == (approve ? .completed : .pending))
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == (approve ? 1 : 0))
        #expect(secondTrigger.revision == 0)
    }

    @Test("审核保存失败保留队列和等待，不发布成功或通知，之后可以重试", arguments: [false, true])
    func failedSaveKeepsWaiting(approve: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let trigger = NotificationRebuildTrigger()
        let model = fixture.model(trigger: trigger, shouldFailSave: true)
        model.load()
        let item = try #require(fixture.items(from: model).first)
        if approve { model.approve(item) } else { model.returnForRevision(item) }
        #expect(model.actionFailure == .saveFailed && model.isActionErrorPresented && model.feedback == nil)
        #expect(try fixture.items(from: model) == [item])
        #expect(trigger.revision == 0 && !fixture.context.hasChanges && occurrence.status == .pending)
        #expect(try TaskSubmissionHistory(context: fixture.context).latest(for: occurrence)?.reviewState == .waiting)
        #expect(occurrence.timerSessions.first?.state == .ended)
        try fixture.expectNoReward()
        let retry = fixture.model(trigger: trigger)
        retry.load()
        if approve { retry.approve(item) } else { retry.returnForRevision(item) }
        #expect(try fixture.items(from: retry).isEmpty && !retry.isActionErrorPresented && trigger.revision == 1)
    }

    @Test("已有未保存编辑拒绝审核且不回滚用户内容", arguments: [false, true])
    func dirtyContextIsNotRolledBack(approve: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let trigger = NotificationRebuildTrigger()
        let model = fixture.model(trigger: trigger)
        model.load()
        let item = try #require(fixture.items(from: model).first)
        occurrence.titleSnapshot = "合成未保存编辑"
        if approve { model.approve(item) } else { model.returnForRevision(item) }
        #expect(model.actionFailure == .unavailable && model.isActionErrorPresented && model.feedback == nil)
        #expect(fixture.context.hasChanges && occurrence.titleSnapshot == "合成未保存编辑" && trigger.revision == 0)
        try fixture.expectNoReward()
    }

    @Test("坏队列显示失败，修复后可重试，不降级为空态")
    func damagedQueueCanRetryAfterRepair() throws {
        let fixture = try ParentReviewFixture()
        _ = try fixture.makeWaiting()
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        row.reviewStateRawValue = "synthetic-invalid"
        try fixture.context.save()
        let model = fixture.model()
        model.load()
        #expect(model.state == .failed && model.feedback == nil)
        row.reviewStateRawValue = SubmissionReviewState.waiting.rawValue
        try fixture.context.save()
        model.load()
        #expect(try fixture.items(from: model).count == 1 && model.feedback == nil)
    }

    @Test("审核时钟倒退拒绝，原提交保持等待")
    func backwardsClockDoesNotReview() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let trigger = NotificationRebuildTrigger()
        let model = fixture.model(at: fixture.now.addingTimeInterval(-1), trigger: trigger)
        model.load()
        model.approve(try fixture.item(for: occurrence))
        #expect(model.actionFailure == .unavailable && model.feedback == nil && trigger.revision == 0)
        #expect(try fixture.items(from: model).count == 1)
        try fixture.expectNoReward()
    }

    @Test("审核已保存后队列读取失败不伪报保存失败，真实奖励与通知仍保留")
    func successfulReviewDoesNotBecomeSaveFailure() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let trigger = NotificationRebuildTrigger()
        let model = fixture.model(trigger: trigger)
        model.load()
        let item = try fixture.item(for: occurrence)
        // 另一个坏审计使全队列刷新失败，但不能把已经保存的审核当作未结算重试。
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: fixture.now, reminderAt: fixture.now, xp: 0, baseCoins: 0, autonomyBonusCoins: 0)
        fixture.context.insert(
            TaskSubmission(
                occurrenceID: V0MigrationFixture.orphanID, sequenceNumber: 1, snapshot: snapshot,
                activeDurationSeconds: 0))
        try fixture.context.save()
        model.approve(item)
        #expect(model.state == .failed && model.feedback == nil)
        #expect(model.actionFailure == nil && !model.isActionErrorPresented && trigger.revision == 1)
        #expect(occurrence.status == .completed && !fixture.context.hasChanges)
        #expect(
            try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
    }

    @Test("通过被撤销后清空过时反馈，不从历史重新庆祝")
    func revokedApprovalClearsLocalFeedback() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let model = fixture.model()
        model.load()
        let item = try fixture.item(for: occurrence)
        model.approve(item)
        let id = try #require(model.feedback?.result.completionID)
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: id, at: fixture.now.addingTimeInterval(1))
        model.refresh()
        let refreshedItems = try fixture.items(from: model)
        #expect(model.feedback == nil && refreshedItems.isEmpty)
        model.approve(item)
        #expect(model.feedback == nil && !model.isActionErrorPresented)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
    }

    @Test("等待磁盘重开审核，保存成功或失败再重开不重播反馈", arguments: [false, true], [false, true])
    func diskReviewDoesNotReplay(approve: Bool, shouldFail: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let submissionID = try seedDiskWaiting(at: url)
        try reviewDisk(at: url, submissionID: submissionID, approve: approve, shouldFail: shouldFail)
        for _ in 0..<2 {
            let fixture = try ParentReviewFixture(storeURL: url)
            let model = fixture.model()
            model.load()
            #expect(model.feedback == nil && !model.isActionErrorPresented)
            let items = try fixture.items(from: model)
            #expect(items.count == (shouldFail ? 1 : 0))
            #expect(items.first?.id == (shouldFail ? submissionID : nil))
            #expect(
                try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == (approve && !shouldFail ? 1 : 0))
            #expect(
                try RewardLedgerService(context: fixture.context).balance()
                    == RewardBalance(
                        effectiveXP: approve && !shouldFail ? 11 : 0, coins: approve && !shouldFail ? 10 : 0))
        }
    }

    private func seedDiskWaiting(at url: URL) throws -> UUID {
        let fixture = try ParentReviewFixture(storeURL: url)
        let occurrence = try fixture.makeWaiting(day: "2026-09-22")
        return try fixture.item(for: occurrence).id
    }

    private func reviewDisk(at url: URL, submissionID: UUID, approve: Bool, shouldFail: Bool) throws {
        let fixture = try ParentReviewFixture(storeURL: url)
        let trigger = NotificationRebuildTrigger()
        let model = fixture.model(
            at: fixture.now.addingTimeInterval(86400), trigger: trigger, shouldFailSave: shouldFail)
        model.load()
        let item = try #require(fixture.items(from: model).first)
        #expect(item.id == submissionID && model.feedback == nil && item.expectedXP == 11 && item.expectedCoins == 10)
        if approve { model.approve(item) } else { model.returnForRevision(item) }
        #expect(model.isActionErrorPresented == shouldFail && trigger.revision == (shouldFail ? 0 : 1))
        #expect((model.feedback != nil) == !shouldFail)
    }
}
