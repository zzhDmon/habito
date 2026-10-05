import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("任务执行页计时恢复")
struct TaskSessionViewModelTests {
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
