import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("未开始任务删除事务")
@MainActor
struct TaskDeletionServiceTests {
    @Test("单次取消保留唯一键，重建和模板改名都不会复活")
    func occurrenceDeletionSurvivesReconciliation() throws {
        let f = try Fixture()
        let tomorrow = try f.insert(on: "2026-09-24")
        try f.delete(.occurrence)
        #expect(f.occurrence.status == .cancelled && f.template.isEnabled)
        f.template.title = "新标题"
        f.template.revision += 1
        try f.context.save()
        for _ in 0..<2 {
            _ = try f.materializer.reconcile(template: f.template, today: f.today, now: f.now)
        }
        #expect(f.occurrence.status == .cancelled)
        #expect(tomorrow.status == .pending && tomorrow.titleSnapshot == "新标题")
        #expect(try f.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 2)
        let snapshot = try f.query.snapshot(for: f.today, at: f.now)
        #expect(snapshot.tasks.isEmpty && snapshot.totalCount == 0)
        let statistics = try GrowthStatisticsQueryService(
            context: f.context, calendar: f.calendar, timeZone: f.timeZone
        ).today(at: f.now)
        #expect(statistics.counts.eligible == 0)
    }

    @Test("取消本次后日历覆盖与恢复不复活，预览不虚报保留任务")
    func calendarOverridePreservesCancellationWithoutVisibleCounts() throws {
        let f = try Fixture()
        try f.delete(.occurrence)
        let calendar = ParentCalendarDayService(context: f.context, calendar: f.calendar, timeZone: f.timeZone)
        for action in [ParentCalendarDayAction.setHoliday, .removeOverride] {
            let impact = try calendar.preview(action, on: f.today, today: f.today)
            #expect(impact.insertedCount == 0 && impact.deletedCount == 0 && impact.protectedCount == 0)
            _ = try calendar.apply(action, on: f.today, today: f.today, now: f.now)
            #expect(try calendar.snapshot(for: f.today, today: f.today).occurrences.isEmpty)
            #expect(f.occurrence.status == .cancelled)
            #expect(try f.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
        }
    }

    @Test("周期取消包含未来单日覆盖和跳过，保留历史与已经开始任务")
    func seriesPreservesHistoryAndStarted() throws {
        let f = try Fixture()
        let historical = try f.insert(on: "2026-09-22")
        let detached = try f.insert(on: "2026-09-24")
        detached.isDetachedOverride = true
        let skipped = try f.insert(on: "2026-09-25")
        skipped.statusRawValue = TaskOccurrenceStatus.skipped.rawValue
        let begun = try f.insert(on: "2026-09-26")
        begun.statusRawValue = TaskOccurrenceStatus.inProgress.rawValue
        try f.context.save()
        try f.delete(.series)
        #expect(f.template.archivedAt == f.now && !f.template.isEnabled)
        #expect(f.template.reminderRule?.isEnabled == false)
        #expect(f.occurrence.status == .cancelled && detached.status == .cancelled && skipped.status == .cancelled)
        #expect(historical.status == .pending && begun.status == .inProgress)
        _ = try f.materializer.reconcile(template: f.template, today: f.today, now: f.now)
        #expect(try f.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 5)
    }

    @Test("开始、完成、取消及历史实例拒绝再次删除", arguments: [0, 1, 2, 3])
    func staleOrHistoricalSelectionRejected(kind: Int) throws {
        let f = try Fixture()
        if kind < 3 {
            f.occurrence.statusRawValue = [TaskOccurrenceStatus.inProgress, .completed, .cancelled][kind].rawValue
            try f.context.save()
        }
        let today = kind == 3 ? try LocalDate(dateKey: "2026-09-24") : f.today
        #expect(throws: TaskDeletionError.self) {
            try TaskDeletionService(context: f.context).delete(
                occurrenceID: f.occurrence.id, scope: .occurrence, today: today, now: f.now)
        }
        #expect(f.template.isEnabled && !f.context.hasChanges)
    }

    @Test("提交等待与退回都不等于从未开始", arguments: [false, true])
    func submissionHistoryPreventsDeletion(returned: Bool) throws {
        let f = try Fixture()
        f.occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try f.context.save()
        let submission = try TaskSubmissionService(context: f.context).submit(f.occurrence, at: f.now)
        if returned {
            _ = try TaskSubmissionReviewService(context: f.context).returnForRevision(
                f.occurrence, submissionID: submission.submissionID, at: f.now)
        }
        #expect(try !TaskDeletionService.canDelete(f.occurrence, context: f.context))
        #expect(throws: TaskDeletionError.self) { try f.delete(.series) }
        #expect(f.template.isEnabled && f.occurrence.status == .pending)
    }

    @Test("周期删除不改写已完成奖励及撤销审计")
    func seriesPreservesRewardsAndRevokedHistory() throws {
        let f = try Fixture()
        let completed = try f.insert(on: "2026-09-24")
        let revoked = try f.insert(on: "2026-09-25")
        for row in [completed, revoked] { row.xpRewardSnapshot = 11; row.coinRewardSnapshot = 7 }
        try f.context.save()
        let service = TaskCompletionService(context: f.context)
        _ = try service.complete(completed, at: f.now, source: .childManual)
        let result = try service.complete(revoked, at: f.now, source: .childManual)
        _ = try TaskCompletionUndoService(context: f.context).undo(
            revoked, completionID: result.completionID, at: f.now)
        let balance = try RewardLedgerService(context: f.context).balance()
        try f.delete(.series)
        #expect(completed.status == .completed && revoked.status == .pending)
        #expect(try RewardLedgerService(context: f.context).balance() == balance)
        #expect(try f.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 2)
        #expect(try !TaskDeletionService.canDelete(revoked, context: f.context))
    }

    @Test("当前规则损坏不阻断已完成实例的历史读取")
    func completedSnapshotDoesNotDecodeCurrentTemplateRule() throws {
        let f = try Fixture()
        _ = try TaskCompletionService(context: f.context).complete(f.occurrence, at: f.now, source: .childManual)
        f.template.reminderRule?.scheduleTypeRawValue = "invalid-current-rule"
        try f.context.save()
        let item = try f.query.item(id: f.occurrence.id, at: f.now)
        #expect(item.status == .completed && !item.canDelete && !item.isRecurring)
    }

    @Test("一次性任务拒绝周期范围")
    func onceRejectsSeries() throws {
        let f = try Fixture()
        let rule = try #require(f.template.reminderRule)
        // 使用正式规则更新入口，避免重复唯一键的夹具触发SwiftData upsert而失去关系。
        rule.update(recurrence: .once(on: f.today), timeOfDayMinutes: 1170, isEnabled: true)
        try f.context.save()
        #expect(throws: TaskDeletionError.self) { try f.delete(.series) }
        try f.delete(.occurrence)
        #expect(f.occurrence.status == .cancelled)
    }

    @Test("有结束计时的pending实例仍不可删除")
    func timerHistoryPreventsDeletion() throws {
        let f = try Fixture()
        let session = TimerSession(
            occurrenceID: f.occurrence.id, state: .ended, startedAt: f.now, lastResumedAt: f.now,
            accumulatedActiveSeconds: 0, endedAt: f.now)
        f.context.insert(session)
        session.occurrence = f.occurrence
        try f.context.save()
        #expect(throws: TaskDeletionError.self) { try f.delete(.occurrence) }
    }

    @Test("保存失败恢复全部标量及模板状态", arguments: [TaskDeletionScope.occurrence, .series])
    func failedSaveRestoresAllState(scope: TaskDeletionScope) throws {
        let f = try Fixture()
        let future = try f.insert(on: "2026-09-24")
        let revision = f.template.revision
        let service = TaskDeletionService(context: f.context, saveChanges: { throw CocoaError(.fileWriteUnknown) })
        #expect(throws: CocoaError.self) {
            try service.delete(occurrenceID: f.occurrence.id, scope: scope, today: f.today, now: f.now)
        }
        #expect(f.occurrence.status == .pending && future.status == .pending)
        #expect(f.template.isEnabled && f.template.archivedAt == nil && f.template.revision == revision)
        #expect(f.template.reminderRule?.isEnabled == true && !f.context.hasChanges)
    }

    @Test("未保存编辑不被删除操作回滚")
    func dirtyContextPreserved() throws {
        let f = try Fixture()
        f.template.title = "未保存编辑"
        #expect(throws: TaskDeletionError.self) { try f.delete(.series) }
        #expect(f.template.title == "未保存编辑" && f.context.hasChanges)
        #expect(f.occurrence.status == .pending)
    }

    @Test("删除成功通知重建一次，重复请求失败且不发通知")
    func viewModelRefreshesOnlyAfterSuccess() throws {
        let f = try Fixture()
        let trigger = NotificationRebuildTrigger()
        let model = ParentTodayTaskViewModel(
            context: f.context, calendar: f.calendar, timeZone: f.timeZone,
            dateProvider: FixedDateProvider(value: f.now), notificationRebuildTrigger: trigger)
        model.delete(occurrenceID: f.occurrence.id, scope: .occurrence)
        #expect(trigger.revision == 1 && !model.isActionErrorPresented)
        model.delete(occurrenceID: f.occurrence.id, scope: .occurrence)
        #expect(trigger.revision == 1 && model.isActionErrorPresented)
    }

    @Test("取消记录磁盘重开并再次重建仍保持", arguments: [TaskDeletionScope.occurrence, .series])
    func diskRestartPreservesDeletion(scope: TaskDeletionScope) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let id = try seedDeletion(at: url, scope: scope)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            let row = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.id == id })
            let template = try #require(row.template)
            let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            _ = try TaskOccurrenceMaterializationService(
                context: context, calendar: Calendar(identifier: .gregorian), timeZone: zone
            ).reconcile(
                template: template, today: LocalDate(dateKey: "2026-09-23"),
                now: Date("2026-09-23T04:00:00Z", strategy: .iso8601))
            #expect(row.status == .cancelled)
            #expect(template.isEnabled == (scope == .occurrence))
        }
    }

    private func seedDeletion(at url: URL, scope: TaskDeletionScope) throws -> UUID {
        let f = try Fixture(storeURL: url)
        try f.delete(scope)
        return f.occurrence.id
    }

    private final class Fixture {
        let context: ModelContext
        let calendar = Calendar(identifier: .gregorian)
        let timeZone: TimeZone
        let now: Date
        let today: LocalDate
        let template: TaskTemplate
        let occurrence: TaskOccurrence
        var materializer: TaskOccurrenceMaterializationService {
            TaskOccurrenceMaterializationService(context: context, calendar: calendar, timeZone: timeZone)
        }
        var query: TodayTaskQueryService {
            TodayTaskQueryService(context: context, calendar: calendar, timeZone: timeZone)
        }

        init(storeURL: URL? = nil) throws {
            context = ModelContext(
                try storeURL.map { try AppModelContainer.make(storeURL: $0) } ?? AppModelContainer.make(inMemory: true))
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
            today = try LocalDate(dateKey: "2026-09-23")
            template = TaskTemplate(
                title: "阅读", iconName: "book.fill", colorToken: "reading", targetDurationSeconds: 900, createdAt: now,
                updatedAt: now)
            let rule = ReminderRule(
                taskTemplateID: template.id, recurrence: try .weekly(on: Set(Weekday.allCases), starting: today),
                timeOfDayMinutes: 1170)
            occurrence = TaskOccurrence(
                templateID: template.id, date: today, scheduledAt: now.addingTimeInterval(3600),
                titleSnapshot: template.title, iconSnapshot: template.iconName, colorSnapshot: template.colorToken,
                targetDurationSnapshot: 900, sourceRevision: template.revision, createdAt: now, updatedAt: now)
            context.insert(template); context.insert(rule); context.insert(occurrence)
            template.reminderRule = rule; rule.taskTemplate = template; occurrence.template = template
            try context.save()
        }

        func insert(on key: String) throws -> TaskOccurrence {
            let row = TaskOccurrence(
                templateID: template.id, date: try LocalDate(dateKey: key), scheduledAt: now,
                titleSnapshot: template.title, iconSnapshot: template.iconName, colorSnapshot: template.colorToken,
                targetDurationSnapshot: 900, sourceRevision: template.revision, createdAt: now, updatedAt: now)
            context.insert(row); row.template = template
            try context.save()
            return row
        }

        func delete(_ scope: TaskDeletionScope) throws {
            try TaskDeletionService(context: context).delete(
                occurrenceID: occurrence.id, scope: scope, today: today, now: now)
        }
    }
}
