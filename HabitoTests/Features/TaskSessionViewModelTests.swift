import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("任务执行页计时恢复")
struct TaskSessionViewModelTests {
    @Test("孩子提交后等待或退回真实磁盘重开，页面派生正确且不重播收据", arguments: [false, true])
    func diskReentryDoesNotReplaySubmissionFeedback(returned: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let submissionID = try seedSubmissionPage(at: url, returned: returned)
        let now = try Date("2026-09-23T04:00:01Z", strategy: .iso8601)
        let calendar = Calendar(identifier: .gregorian)
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let model = TaskSessionViewModel(
                occurrenceID: V0MigrationFixture.pendingID, context: context,
                calendar: calendar, timeZone: zone, dateProvider: FixedDateProvider(value: now))
            model.load()
            let content = try loadedContent(from: model.state)
            #expect(content.isAwaitingReview == !returned && content.canComplete == returned)
            #expect(content.submission?.id == submissionID && content.verificationType == .parentApproval)
            #expect(content.submission?.expectedXP == 11 && content.submission?.expectedCoins == 10)
            #expect(model.completionFeedback == nil)
            #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            #expect(try RewardLedgerService(context: context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        }
    }

    @Test("家长验收页面提交只等待且禁旧动作，零奖励也正常判自主", arguments: [false, true])
    func approvalTaskProducesSubmissionNotReward(zero: Bool) async throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "合成家长验收", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        occurrence.xpRewardSnapshot = zero ? 0 : 11
        occurrence.coinRewardSnapshot = zero ? 0 : 7
        occurrence.activeBonusCoinSnapshot = zero ? 0 : 3
        try fixture.context.save()
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        #expect(try loadedContent(from: model.state).verificationType == .parentApproval)
        model.completeTask()
        let waiting = try loadedContent(from: model.state)
        #expect(waiting.isAwaitingReview && !waiting.canComplete && waiting.primaryAction == .none)
        #expect(!waiting.canUndoCompletion(at: fixture.now) && waiting.completion == nil)
        guard case let .submitted(receipt) = model.completionFeedback else {
            Issue.record("提交不能发布已到账反馈"); return
        }
        #expect(receipt.didSubmit && receipt.timing == .beforeReminder)
        #expect(waiting.submission?.id == receipt.submissionID)
        #expect(waiting.submission?.expectedXP == (zero ? 0 : 11))
        #expect(waiting.submission?.expectedCoins == (zero ? 0 : 10))
        model.completeTask()
        model.startOrResume()
        model.pause()
        model.undoCompletion()
        await model.snooze()
        #expect(trigger.revision == 1 && !model.isActionErrorPresented)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
        #expect(try completionRecords(in: fixture.context, occurrenceID: occurrence.id).isEmpty)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        model.dismissCompletionFeedback()
        model.refresh()
        #expect(model.completionFeedback == nil)
        let reentered = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        reentered.load()
        #expect(try loadedContent(from: reentered.state).isAwaitingReview && reentered.completionFeedback == nil)
    }

    @Test("运行或暂停的家长任务提交结束计时并保留累计时长", arguments: [TimerSessionState.running, .paused])
    func approvalSubmissionEndsTiming(state: TimerSessionState) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "计时后提交", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        let progress = TaskProgressService(context: fixture.context)
        _ = try progress.startTiming(for: occurrence, at: fixture.now.addingTimeInterval(-120))
        if state == .paused { _ = try progress.pauseTiming(for: occurrence, at: fixture.now.addingTimeInterval(-60)) }
        let model = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        model.load()
        model.completeTask()
        let content = try loadedContent(from: model.state)
        #expect(content.isAwaitingReview && content.activeSessionState == nil)
        #expect(content.activeDurationAtSnapshot == (state == .running ? 120 : 60))
        #expect(content.submission?.activeDurationSeconds == content.activeDurationAtSnapshot)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).first?.state == .ended)
    }

    @Test("自行确认反馈只包含实际收据，零奖励仍是真实完成；撤销后清空旧事件", arguments: [false, true])
    func completedFeedbackContainsActualReceipt(zero: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "真实完成反馈", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.xpRewardSnapshot = zero ? 0 : 11
        occurrence.coinRewardSnapshot = zero ? 0 : 7
        occurrence.activeBonusCoinSnapshot = zero ? 0 : 3
        try fixture.context.save()
        let model = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        model.load()
        model.completeTask()
        guard case let .completed(receipt) = model.completionFeedback else {
            Issue.record("自行确认应发布真实完成收据"); return
        }
        #expect(receipt.didComplete && receipt.xp == (zero ? 0 : 11) && receipt.coins == (zero ? 0 : 10))
        #expect(receipt.completionID == (try loadedContent(from: model.state).completion?.id))
        model.undoCompletion()
        #expect(model.completionFeedback == nil && occurrence.status == .pending)
        model.completeTask()
        #expect(model.completionFeedback?.id != receipt.completionID)
        model.dismissCompletionFeedback()
        model.refresh()
        model.completeTask()
        #expect(model.completionFeedback == nil)
    }

    @Test("页面加载后验收类型变更，以重新读取配置路由，不用旧页面判断", arguments: [false, true])
    func staleConfigurationUsesCurrentVerification(wasApproval: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "陈旧配置页面", scheduledAt: fixture.now, status: .pending)
        occurrence.verificationTypeSnapshotRawValue =
            (wasApproval ? TaskVerificationType.parentApproval : .selfConfirm).rawValue
        try fixture.context.save()
        let model = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        model.load()
        occurrence.verificationTypeSnapshotRawValue =
            (wasApproval ? TaskVerificationType.selfConfirm : .parentApproval).rawValue
        try fixture.context.save()
        model.completeTask()
        #expect(!model.isActionErrorPresented)
        #expect((occurrence.status == .completed) == wasApproval)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == (wasApproval ? 0 : 1))
    }

    @Test("陈旧页面遇到外部提交/通过，只刷新当前事实，不发布新成功事件", arguments: [false, true])
    func stalePageDoesNotRepeatExternalSubmissionOrApproval(approve: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "另页已操作", scheduledAt: fixture.now, status: .pending)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        let row = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        if approve {
            _ = try TaskSubmissionReviewService(context: fixture.context).approve(
                occurrence, submissionID: row.submissionID, at: fixture.now)
        }
        // 等待时后来改为自行确认仍不能绕过原审核事实。
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.selfConfirm.rawValue
        try fixture.context.save()
        model.completeTask()
        #expect(trigger.revision == 0 && model.completionFeedback == nil && !model.isActionErrorPresented)
        #expect(try loadedContent(from: model.state).isAwaitingReview == !approve)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
        #expect(try completionRecords(in: fixture.context, occurrenceID: occurrence.id).count == (approve ? 1 : 0))
    }

    @Test("退回后刷新释放动作，重提新轮次，不重播原提交反馈")
    func returnedTaskCanResumeAndResubmitWithNewEvent() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "再完善一下", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        model.completeTask()
        let firstID = try #require(model.completionFeedback?.id)
        _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
            occurrence, submissionID: firstID, at: fixture.now)
        model.refresh()
        let returned = try loadedContent(from: model.state)
        #expect(!returned.isAwaitingReview && returned.canComplete && returned.primaryAction == .start)
        #expect(model.completionFeedback == nil && returned.submission?.state == .returned)
        model.startOrResume()
        model.completeTask()
        #expect(try loadedContent(from: model.state).isAwaitingReview)
        #expect(model.completionFeedback?.id != firstID && trigger.revision == 3)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 2)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
    }

    @Test("提交保存失败不发布反馈或重建，原执行事实保留且可重试", arguments: [false, true])
    func submissionSaveFailureDoesNotPublishSuccess(active: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "提交保存边界", scheduledAt: fixture.now, status: .pending)
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        if active {
            _ = try TaskProgressService(context: fixture.context).startTiming(
                for: occurrence, at: fixture.now.addingTimeInterval(-60))
        }
        let trigger = NotificationRebuildTrigger()
        let model = TaskSessionViewModel(
            occurrenceID: occurrence.id, context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone, dateProvider: FixedDateProvider(value: fixture.now),
            notificationRebuildTrigger: trigger,
            submissionService: TaskSubmissionService(
                context: fixture.context, saveChanges: { _ in throw CocoaError(.fileWriteUnknown) }))
        model.load()
        model.completeTask()
        #expect(model.actionFailure == .saveFailed && model.isActionErrorPresented)
        #expect(model.completionFeedback == nil && trigger.revision == 0)
        #expect(
            try loadedContent(from: model.state).canComplete && occurrence.status == (active ? .inProgress : .pending))
        if active { #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).first?.state == .running) }
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("坏验收配置加载明确失败，加载后损坏也不能静默按自行确认发奖")
    func invalidVerificationDoesNotFallback() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "配置损坏", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        let model = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        model.load()
        occurrence.verificationTypeSnapshotRawValue = "corrupt"
        try fixture.context.save()
        model.completeTask()
        #expect(model.actionFailure == .unavailable && model.isActionErrorPresented && model.completionFeedback == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        model.refresh()
        #expect(model.state == .failed)
        #expect(throws: TodayTaskQueryError.invalidVerificationType(occurrenceID: occurrence.id, value: "corrupt")) {
            try TodayTaskQueryService(context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
                .item(id: occurrence.id, at: fixture.now)
        }
    }

    @Test("计时显示与完成撤销判断共用注入时钟")
    func renderedTimeUsesSameClockAsBusinessWrites() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "阅读", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        _ = try TaskProgressService(context: fixture.context).startTiming(
            for: occurrence, at: fixture.now.addingTimeInterval(-120))
        let model = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        model.load()
        #expect(model.currentDate() == fixture.now)
        #expect(try loadedContent(from: model.state).displayedActiveDuration(at: model.currentDate()) == 120)
        model.completeTask()
        #expect(try loadedContent(from: model.state).canUndoCompletion(at: model.currentDate()))
        model.undoCompletion()
        #expect(occurrence.status == .pending)
    }

    @Test("提前开始任务只请求一次主提醒清理，重复点击和暂停继续不重复触发")
    func startingFutureTaskRequestsRebuildExactlyOnce() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "阅读", scheduledAt: fixture.now.addingTimeInterval(900), status: .pending)
        try fixture.context.save()
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        model.startOrResume()
        #expect(trigger.revision == 1)
        #expect(occurrence.status == .inProgress)
        model.startOrResume()
        #expect(trigger.revision == 1)
        model.pause()
        model.startOrResume()
        #expect(trigger.revision == 1)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).count == 1)
    }

    @Test("加载后实例被删除导致开始失败时，不发出成功写入的重建事件")
    func failedStartDoesNotRequestRebuild() throws {
        let fixture = try TodayQueryFixture()
        let second = fixture.makeOccurrence(title: "准备口算", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: second.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        let occurrenceID = second.id
        fixture.context.delete(second)
        try fixture.context.save()
        model.startOrResume()
        #expect(trigger.revision == 0)
        #expect(model.state == .failed)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrenceID).isEmpty)
    }

    @Test("通知被拒绝时展示可理解反馈并请求核对，仍能手动完成")
    func deniedSnoozeKeepsManualCompletionAvailable() async throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "阅读", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        let provider = UITestNotificationPermissionProvider(deniesAuthorization: true)
        let trigger = NotificationRebuildTrigger()
        let model = TaskSessionViewModel(
            occurrenceID: occurrence.id,
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now),
            snoozeService: TaskSnoozeService(
                context: fixture.context, scheduler: provider, permissionProvider: provider,
                calendar: fixture.calendar, timeZone: fixture.timeZone
            ),
            notificationRebuildTrigger: trigger
        )
        model.load()
        await model.snooze()
        #expect(model.snoozeState == .notificationsDisabled)
        #expect(trigger.revision == 1)
        model.completeTask()
        #expect(try loadedContent(from: model.state).task.status == .completed)
        #expect(model.snoozeState == .idle)
    }

    @Test("开始任务只创建一个活动会话")
    func startCreatesOnlyOneActiveSession() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "阅读",
            scheduledAt: fixture.now,
            status: .pending
        )
        try fixture.context.save()
        let model = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)

        model.load()
        #expect(try loadedContent(from: model.state).primaryAction == .start)

        model.startOrResume()
        model.startOrResume()

        let content = try loadedContent(from: model.state)
        #expect(content.task.status == .inProgress)
        #expect(content.primaryAction == .pause)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).count == 1)
    }

    @Test("暂停后锁屏两分钟不增长，继续后按时间戳恢复且不重复会话")
    func pauseAndResumeRecoverFromPersistedTimestamps() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "练字",
            scheduledAt: fixture.now,
            status: .pending
        )
        try fixture.context.save()
        let startedAt = fixture.now.addingTimeInterval(-120)
        _ = try TaskProgressService(context: fixture.context).startTiming(
            for: occurrence,
            at: startedAt
        )

        let runningModel = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        runningModel.load()
        let running = try loadedContent(from: runningModel.state)
        #expect(running.displayedActiveDuration(at: fixture.now) == 120)

        runningModel.pause()
        let lockedUntil = fixture.now.addingTimeInterval(120)
        let lockedModel = makeModel(for: occurrence.id, fixture: fixture, now: lockedUntil)
        lockedModel.load()
        let paused = try loadedContent(from: lockedModel.state)
        #expect(paused.primaryAction == .resume)
        #expect(paused.displayedActiveDuration(at: lockedUntil) == 120)

        lockedModel.startOrResume()
        let foregroundAt = lockedUntil.addingTimeInterval(60)
        let restoredModel = makeModel(for: occurrence.id, fixture: fixture, now: foregroundAt)
        restoredModel.load()
        let restored = try loadedContent(from: restoredModel.state)
        #expect(restored.primaryAction == .pause)
        #expect(restored.displayedActiveDuration(at: foregroundAt) == 180)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).count == 1)
    }

    @Test("实例被移除后加载进入可重试错误态")
    func missingOccurrenceProducesFailureState() throws {
        let fixture = try TodayQueryFixture()
        let model = makeModel(for: UUID(), fixture: fixture, now: fixture.now)

        model.load()

        #expect(model.state == .failed)
    }

    @Test("运行中完成会保存实际时长并结束计时会话")
    func completionPersistsDurationAndEndsSession() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "口算",
            scheduledAt: fixture.now,
            status: .pending
        )
        try fixture.context.save()
        _ = try TaskProgressService(context: fixture.context).startTiming(
            for: occurrence,
            at: fixture.now.addingTimeInterval(-120)
        )
        let rebuildTrigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id,
            fixture: fixture,
            now: fixture.now,
            notificationRebuildTrigger: rebuildTrigger
        )
        model.load()

        model.completeTask()

        let content = try loadedContent(from: model.state)
        let completion = try #require(content.completion)
        #expect(content.task.status == .completed)
        #expect(completion.activeDurationSeconds == 120)
        #expect(completion.source == .childManual)
        #expect(content.canUndoCompletion(at: fixture.now))
        #expect(content.undoRemainingSeconds(at: fixture.now) == 5)
        #expect(try sessions(in: fixture.context, occurrenceID: occurrence.id).first?.state == .ended)
        #expect(try completionRecords(in: fixture.context, occurrenceID: occurrence.id).count == 1)
        #expect(try snapshot(in: fixture).completedCount == 1)
        #expect(rebuildTrigger.revision == 1)
    }

    @Test("完成后五秒内撤销保留审计记录并恢复待处理")
    func undoWithinWindowRestoresPendingState() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "背诗",
            scheduledAt: fixture.now,
            status: .pending
        )
        try fixture.context.save()
        let completionModel = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        completionModel.load()
        completionModel.completeTask()

        let undoAt = fixture.now.addingTimeInterval(4)
        let rebuildTrigger = NotificationRebuildTrigger()
        let undoModel = makeModel(
            for: occurrence.id,
            fixture: fixture,
            now: undoAt,
            notificationRebuildTrigger: rebuildTrigger
        )
        undoModel.load()
        #expect(try loadedContent(from: undoModel.state).undoRemainingSeconds(at: undoAt) == 1)

        undoModel.undoCompletion()

        let content = try loadedContent(from: undoModel.state)
        #expect(content.task.status == .pending)
        #expect(content.completion == nil)
        let records = try completionRecords(in: fixture.context, occurrenceID: occurrence.id)
        #expect(records.count == 1 && records.first?.revokedAt == undoAt)
        #expect(try snapshot(in: fixture, at: undoAt).completedCount == 0)
        #expect(rebuildTrigger.revision == 1)
    }

    @Test("完成五秒后撤销不会改写完成事实")
    func undoAfterWindowLeavesCompletionUntouched() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "整理书包",
            scheduledAt: fixture.now,
            status: .pending
        )
        try fixture.context.save()
        let completionModel = makeModel(for: occurrence.id, fixture: fixture, now: fixture.now)
        completionModel.load()
        completionModel.completeTask()

        let expiredAt = fixture.now.addingTimeInterval(5)
        let expiredModel = makeModel(for: occurrence.id, fixture: fixture, now: expiredAt)
        expiredModel.load()
        let expiredContent = try loadedContent(from: expiredModel.state)
        #expect(!expiredContent.canUndoCompletion(at: expiredAt))
        #expect(expiredContent.undoRemainingSeconds(at: expiredAt) == 0)

        expiredModel.undoCompletion()

        #expect(try loadedContent(from: expiredModel.state).task.status == .completed)
        #expect(try completionRecords(in: fixture.context, occurrenceID: occurrence.id).count == 1)
        #expect(try snapshot(in: fixture, at: expiredAt).completedCount == 1)
    }

    @Test("页面完成显式奖励只结算一次，撤销重完保留历史且今日只取当前事实")
    func rewardCompletionUndoAndRecompletionUseCurrentFact() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "显式奖励", scheduledAt: fixture.now.addingTimeInterval(60), status: .pending)
        occurrence.xpRewardSnapshot = 11
        occurrence.coinRewardSnapshot = 7
        occurrence.activeBonusCoinSnapshot = 3
        try fixture.context.save()
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        model.completeTask()
        let originalID = try #require(try loadedContent(from: model.state).completion?.id)
        model.completeTask()
        #expect(trigger.revision == 1)
        #expect(
            try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
        model.undoCompletion()
        #expect(trigger.revision == 2 && occurrence.status == .pending)
        #expect(try snapshot(in: fixture).completedCount == 0)
        model.completeTask()
        #expect(trigger.revision == 3)
        let current = try #require(try loadedContent(from: model.state).completion)
        #expect(current.id != originalID)
        let history = try completionRecords(in: fixture.context, occurrenceID: occurrence.id)
        #expect(history.count == 2 && history.count { $0.revokedAt != nil } == 1)
        #expect(try snapshot(in: fixture).completedCount == 1)
        #expect(
            try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
    }

    @Test("币不足撤销展示独立提示，原完成仍显示且不重建成功通知")
    func insufficientCoinsKeepCompletedPageAndReportReason() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "已用奖励", scheduledAt: fixture.now, status: .pending)
        occurrence.coinRewardSnapshot = 7
        try fixture.context.save()
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        model.completeTask()
        let id = try #require(try loadedContent(from: model.state).completion?.id)
        _ = try RewardLedgerService(context: fixture.context).spendCoins(
            sourceID: V0MigrationFixture.pendingID, cost: 2, at: fixture.now)
        model.undoCompletion()
        #expect(model.actionFailure == .insufficientCoins && model.isActionErrorPresented)
        #expect(try loadedContent(from: model.state).completion?.id == id)
        #expect(occurrence.status == .completed && trigger.revision == 1)
        #expect(try RewardLedgerService(context: fixture.context).balance().coins == 5)
    }

    @Test("完成和撤销保存失败保留原页面事实，明确未保存且不触发重建", arguments: [false, true])
    func failedSaveDoesNotPublishSuccess(undo: Bool) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "保存边界", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        if undo {
            _ = try TaskCompletionService(context: fixture.context).complete(
                occurrence, at: fixture.now, source: .childManual)
        }
        let trigger = NotificationRebuildTrigger()
        let save: (ModelContext) throws -> Void = { _ in throw NSError(domain: "HabitoSyntheticSave", code: 1) }
        let model = TaskSessionViewModel(
            occurrenceID: occurrence.id, context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone, dateProvider: FixedDateProvider(value: fixture.now),
            notificationRebuildTrigger: trigger,
            completionService: TaskCompletionService(context: fixture.context, saveChanges: save),
            undoService: TaskCompletionUndoService(context: fixture.context, saveChanges: save))
        model.load()
        if undo { model.undoCompletion() } else { model.completeTask() }
        #expect(model.actionFailure == .saveFailed && model.isActionErrorPresented)
        #expect(trigger.revision == 0 && !fixture.context.hasChanges)
        #expect(try loadedContent(from: model.state).task.status == (undo ? .completed : .pending))
        #expect(occurrence.status == (undo ? .completed : .pending))
    }

    @Test("旧页面撤销请求捕获原 ID，不误撤外部重完的新事实")
    func stalePageUndoCannotRevokeNewFact() throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "原事件", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        let completion = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        let trigger = NotificationRebuildTrigger()
        let model = makeModel(
            for: occurrence.id, fixture: fixture, now: fixture.now, notificationRebuildTrigger: trigger)
        model.load()
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: completion.completionID, at: fixture.now)
        let latest = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        model.undoCompletion()
        #expect(occurrence.status == .completed && occurrence.completionRecord?.id == latest.completionID)
        #expect(try loadedContent(from: model.state).completion?.id == latest.completionID)
        #expect(trigger.revision == 0 && !model.isActionErrorPresented)
    }

    /// 固定合成磁盘库与时刻，不使用真实家庭容器或历史记录构造虚假 UI 成功事件。
    private func seedSubmissionPage(at url: URL, returned: Bool) throws -> UUID {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        let now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
        let occurrence = TaskOccurrence(
            id: V0MigrationFixture.pendingID, templateID: V0MigrationFixture.templateID,
            date: try LocalDate(dateKey: "2026-09-23"), scheduledAt: now.addingTimeInterval(60),
            titleSnapshot: "合成提交页面", iconSnapshot: "book.fill", colorSnapshot: "reading", targetDurationSnapshot: 900,
            sourceRevision: 1, createdAt: now, updatedAt: now, verificationTypeSnapshot: .parentApproval,
            xpRewardSnapshot: 11, coinRewardSnapshot: 7, activeBonusCoinSnapshot: 3)
        context.insert(occurrence)
        try context.save()
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let model = TaskSessionViewModel(
            occurrenceID: occurrence.id, context: context,
            calendar: Calendar(identifier: .gregorian), timeZone: zone, dateProvider: FixedDateProvider(value: now))
        model.load()
        model.completeTask()
        guard case let .submitted(receipt) = model.completionFeedback else {
            Issue.record("合成页面应实际提交成功")
            throw TaskSessionViewModelTestError.expectedLoadedState
        }
        if returned {
            _ = try TaskSubmissionReviewService(context: context).returnForRevision(
                occurrence, submissionID: receipt.submissionID, at: now.addingTimeInterval(1))
        }
        return receipt.submissionID
    }

    private func makeModel(
        for occurrenceID: UUID,
        fixture: TodayQueryFixture,
        now: Date,
        notificationRebuildTrigger: NotificationRebuildTrigger = NotificationRebuildTrigger()
    ) -> TaskSessionViewModel {
        TaskSessionViewModel(
            occurrenceID: occurrenceID,
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: now),
            notificationRebuildTrigger: notificationRebuildTrigger
        )
    }

    private func loadedContent(from state: TaskSessionViewState) throws
        -> TaskSessionScreenContent
    {
        guard case let .loaded(content) = state else {
            Issue.record("预期任务执行页加载成功")
            throw TaskSessionViewModelTestError.expectedLoadedState
        }
        return content
    }

    private func sessions(in context: ModelContext, occurrenceID: UUID) throws -> [TimerSession] {
        let id = occurrenceID
        return try context.fetch(
            FetchDescriptor<TimerSession>(predicate: #Predicate { $0.occurrenceID == id })
        )
    }

    private func completionRecords(
        in context: ModelContext,
        occurrenceID: UUID
    ) throws -> [CompletionRecord] {
        let id = occurrenceID
        return try context.fetch(
            FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.occurrenceID == id })
        )
    }

    private func snapshot(
        in fixture: TodayQueryFixture,
        at now: Date? = nil
    ) throws -> TodayTasksSnapshot {
        try TodayTaskQueryService(
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone
        ).snapshot(for: fixture.date, at: now ?? fixture.now)
    }
}

private enum TaskSessionViewModelTestError: Error {
    case expectedLoadedState
}
