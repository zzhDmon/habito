import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("等待事实保护与只读查询")
struct TaskSubmissionProtectionTests {
    @Test("模板配置传播不改写等待、退回、审核冲正或通过实例", arguments: Array(0..<4))
    func reconciliationKeepsAllAuditedConfiguration(outcome: Int) throws {
        let fixture = try Fixture()
        if outcome == 3 {
            _ = try fixture.review.approve(fixture.occurrence, submissionID: fixture.submissionID, at: fixture.now)
        } else {
            try fixture.applyOutcome(outcome)
        }
        let ordinary = try fixture.makeOccurrence(date: V0MigrationFixture.date("2026-09-23"))
        let originalTime = fixture.occurrence.scheduledAt
        let originalUpdatedAt = fixture.occurrence.updatedAt
        fixture.template.title = "新模板不重算旧提交"
        fixture.template.categoryRawValue = TaskCategory.challenge.rawValue
        fixture.template.timePeriodRawValue = TaskTimePeriod.afterSchool.rawValue
        fixture.template.verificationTypeRawValue = TaskVerificationType.selfConfirm.rawValue
        fixture.template.xpReward = 41
        fixture.template.coinReward = 23
        fixture.template.activeBonusCoin = 9
        fixture.template.revision = 2
        try fixture.context.save()
        let end = try V0MigrationFixture.date("2026-09-23")
        let desired = [fixture.date, end].map {
            ResolvedTaskCandidate(
                date: $0, scheduledAt: fixture.now.addingTimeInterval(7200), origin: .generated(templateRevision: 2))
        }
        let report = try TaskOccurrenceReconciliationService(context: fixture.context).reconcile(
            template: fixture.template, candidates: desired, in: fixture.date...end,
            today: fixture.date, now: fixture.now.addingTimeInterval(10))
        #expect(report.updatedCount == 1 && report.protectedCount == 1)
        #expect(
            ordinary.xpRewardSnapshot == 41 && ordinary.coinRewardSnapshot == 23
                && ordinary.activeBonusCoinSnapshot == 9)
        #expect(ordinary.categorySnapshot == .challenge && ordinary.timePeriodSnapshot == .afterSchool)
        #expect(ordinary.verificationTypeSnapshot == .selfConfirm)
        #expect(fixture.occurrence.categorySnapshot == .unassigned && fixture.occurrence.timePeriodSnapshot == .allDay)
        #expect(fixture.occurrence.verificationTypeSnapshot == .parentApproval)
        #expect(
            fixture.occurrence.xpRewardSnapshot == 11 && fixture.occurrence.coinRewardSnapshot == 7
                && fixture.occurrence.activeBonusCoinSnapshot == 3)
        #expect(fixture.occurrence.scheduledAt == originalTime && fixture.occurrence.updatedAt == originalUpdatedAt)
        #expect(fixture.occurrence.sourceRevision == 1 && fixture.occurrence.titleSnapshot == "合成验收")
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        #expect(
            row.id == fixture.submissionID && row.xpRewardSnapshot == 11 && row.coinRewardSnapshot == 7
                && row.activeBonusCoinSnapshot == 3)
        #expect(row.reminderAtSnapshot == originalTime)
        #expect(!fixture.context.hasChanges)
    }

    @Test("实际运行或暂停计时保留旧配置与会话，不被新模板改变", arguments: [false, true])
    func reconciliationKeepsLiveTimerConfiguration(paused: Bool) throws {
        let fixture = try Fixture()
        let date = try V0MigrationFixture.date("2026-09-23")
        let occurrence = try fixture.makeOccurrence(date: date)
        let progress = TaskProgressService(context: fixture.context)
        let session = try progress.startTiming(for: occurrence, at: fixture.now)
        if paused { _ = try progress.pauseTiming(for: occurrence, at: fixture.now.addingTimeInterval(30)) }
        let originalUpdatedAt = occurrence.updatedAt
        fixture.template.verificationTypeRawValue = TaskVerificationType.parentApproval.rawValue
        fixture.template.xpReward = 11
        fixture.template.coinReward = 7
        fixture.template.activeBonusCoin = 3
        try fixture.context.save()
        let report = try TaskOccurrenceReconciliationService(context: fixture.context).reconcile(
            template: fixture.template,
            candidates: [
                .init(
                    date: date, scheduledAt: fixture.now.addingTimeInterval(7200),
                    origin: .generated(templateRevision: 1))
            ],
            in: date...date, today: fixture.date, now: fixture.now.addingTimeInterval(60))
        #expect(report.protectedCount == 1 && report.updatedCount == 0)
        #expect(occurrence.verificationTypeSnapshot == .selfConfirm && occurrence.xpRewardSnapshot == 0)
        #expect(occurrence.coinRewardSnapshot == 0 && occurrence.activeBonusCoinSnapshot == 0)
        #expect(occurrence.updatedAt == originalUpdatedAt && occurrence.status == .inProgress)
        #expect(session.state == (paused ? .paused : .running))
        #expect(session.accumulatedActiveSeconds == (paused ? 30 : 0))
        #expect(session.endedAt == nil && !fixture.context.hasChanges)
    }

    @Test("自行确认撤销后的完成审计同样保护实例配置，不借 pending 重算")
    func reconciliationKeepsRevokedSelfConfirmationConfiguration() throws {
        let fixture = try Fixture()
        let date = try V0MigrationFixture.date("2026-09-23")
        let occurrence = try fixture.makeOccurrence(date: date)
        let completed = try TaskCompletionService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: completed.completionID, at: fixture.now.addingTimeInterval(1))
        let originalUpdatedAt = occurrence.updatedAt
        fixture.template.verificationTypeRawValue = TaskVerificationType.parentApproval.rawValue
        fixture.template.xpReward = 41
        fixture.template.coinReward = 23
        fixture.template.activeBonusCoin = 9
        try fixture.context.save()
        let report = try TaskOccurrenceReconciliationService(context: fixture.context).reconcile(
            template: fixture.template,
            candidates: [
                .init(
                    date: date, scheduledAt: fixture.now.addingTimeInterval(7200),
                    origin: .generated(templateRevision: 1))
            ],
            in: date...date, today: fixture.date, now: fixture.now.addingTimeInterval(60))
        #expect(report.protectedCount == 1 && report.updatedCount == 0)
        #expect(occurrence.verificationTypeSnapshot == .selfConfirm && occurrence.xpRewardSnapshot == 0)
        #expect(occurrence.coinRewardSnapshot == 0 && occurrence.activeBonusCoinSnapshot == 0)
        #expect(occurrence.updatedAt == originalUpdatedAt && occurrence.status == .pending)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        #expect(!fixture.context.hasChanges)
    }

    @Test("模板修订不更新等待实例，空候选不删除审计实例而普通未来实例仍可清理")
    func reconciliationPreservesWaitingAndKeepsOrdinaryBehavior() throws {
        let fixture = try Fixture()
        let tomorrow = try V0MigrationFixture.date("2026-09-23")
        let ordinary = try fixture.makeOccurrence(date: tomorrow)
        fixture.template.title = "合成模板新标题"
        fixture.template.revision = 2
        try fixture.context.save()
        let candidates = [fixture.date, tomorrow].map {
            ResolvedTaskCandidate(
                date: $0, scheduledAt: fixture.now.addingTimeInterval(7200), origin: .generated(templateRevision: 2))
        }
        let service = TaskOccurrenceReconciliationService(context: fixture.context)
        let changed = try service.reconcile(
            template: fixture.template, candidates: candidates,
            in: fixture.date...tomorrow, today: fixture.date, now: fixture.now)
        #expect(changed.updatedCount == 1 && changed.protectedCount == 1)
        #expect(
            fixture.occurrence.titleSnapshot == "合成验收"
                && fixture.occurrence.scheduledAt == fixture.now.addingTimeInterval(3600))
        #expect(ordinary.titleSnapshot == "合成模板新标题")
        let removed = try service.reconcile(
            template: fixture.template, candidates: [],
            in: fixture.date...tomorrow, today: fixture.date, now: fixture.now)
        #expect(removed.deletedCount == 1 && removed.protectedCount == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).map(\.id) == [fixture.occurrence.id])
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
    }

    @Test("停用或归档预览和执行都保留等待实例", arguments: [TaskTemplateLifecycleAction.disable, .archive])
    func templateLifecyclePreservesWaiting(action: TaskTemplateLifecycleAction) throws {
        let fixture = try Fixture()
        let service = TaskTemplateLifecycleService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
        let impact = try service.preview(templateID: fixture.template.id, action: action, today: fixture.date)
        #expect(impact.removableOccurrenceCount == 0 && impact.preservedOccurrenceCount == 1)
        let performed = try service.perform(
            templateID: fixture.template.id, action: action, today: fixture.date, now: fixture.now)
        let report = try #require(performed.reconciliationReport)
        #expect(report.deletedCount == 0 && report.protectedCount == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
        #expect(try fixture.query.item(id: fixture.occurrence.id, at: fixture.now).isAwaitingReview)
    }

    @Test("放假和撤销放假保留等待或已退回的原实例，预览与执行一致", arguments: [false, true])
    func calendarOverridePreservesSubmissionHistory(returned: Bool) throws {
        let fixture = try Fixture()
        if returned {
            _ = try fixture.review.returnForRevision(
                fixture.occurrence, submissionID: fixture.submissionID, at: fixture.now)
        }
        let service = ParentCalendarDayService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
        let impact = try service.preview(.setHoliday, on: fixture.date, today: fixture.date)
        #expect(impact.deletedCount == 0 && impact.protectedCount == 1)
        let report = try service.apply(.setHoliday, on: fixture.date, today: fixture.date, now: fixture.now)
        #expect(report.deletedCount == 0 && report.protectedCount == 1)
        _ = try service.apply(.removeOverride, on: fixture.date, today: fixture.date, now: fixture.now)
        #expect(try fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).map(\.id) == [fixture.occurrence.id])
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
    }

    @Test("家长单日调时、跳过、恢复和完成更正均不能绕过等待")
    func parentDayActionsCannotBypassWaiting() throws {
        let fixture = try Fixture()
        let service = ParentTodayTaskManagementService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
        let failure = TaskSubmissionError.awaitingReview(fixture.occurrence.id)
        #expect(throws: failure) {
            try service.reschedule(
                occurrenceID: fixture.occurrence.id, to: fixture.now.addingTimeInterval(7200), at: fixture.now)
        }
        #expect(throws: failure) { try service.skip(occurrenceID: fixture.occurrence.id, at: fixture.now) }
        #expect(throws: failure) { try service.restore(occurrenceID: fixture.occurrence.id, at: fixture.now) }
        #expect(throws: failure) {
            try service.correctAsCompleted(occurrenceID: fixture.occurrence.id, at: fixture.now)
        }
        #expect(!fixture.context.hasChanges && !fixture.occurrence.isDetachedOverride)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
    }

    @Test("维护删除拒绝等待、退回或已冲正审计实例，不先断开关系", arguments: [0, 1, 2])
    func physicalDeletionCannotEraseAuditedOccurrence(outcome: Int) throws {
        let fixture = try Fixture()
        try fixture.applyOutcome(outcome)
        let originalTitle = fixture.occurrence.titleSnapshot
        #expect(throws: TaskGraphDeletionError.protectedHistory(fixture.occurrence.id)) {
            try TaskGraphDeletionService(context: fixture.context).stageOccurrenceDeletion(fixture.occurrence)
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskSubmission>()) == 1)
        #expect(
            fixture.occurrence.template?.id == fixture.template.id && fixture.occurrence.titleSnapshot == originalTitle)
        #expect(!fixture.context.hasChanges)
    }

    @Test("等待计入未完成分母但不推荐；普通任务优先，只有等待不能显示全完成")
    func todayQuerySeparatesWaitingFromConfirmedCompletion() throws {
        let fixture = try Fixture()
        let waiting = try fixture.query.snapshot(for: fixture.date, at: fixture.now)
        #expect(
            waiting.totalCount == 1 && waiting.completedCount == 0 && waiting.recommendedTaskID == nil
                && !waiting.isAllCompleted)
        let item = try #require(waiting.tasks.first)
        #expect(item.isAwaitingReview && item.status == .pending && item.completion == nil)
        #expect(
            item.submission?.id == fixture.submissionID && item.submission?.expectedXP == 11
                && item.submission?.expectedCoins == 10)
        let ordinary = try fixture.makeOtherTemplateOccurrence()
        let mixed = try fixture.query.snapshot(for: fixture.date, at: fixture.now)
        #expect(mixed.totalCount == 2 && mixed.completedCount == 0 && mixed.recommendedTaskID == ordinary.id)
        #expect(mixed.tasks.first?.id == ordinary.id)
    }

    @Test("次日通过统计仍归原实例日期，今日没有虚造一次完成")
    func nextDayApprovalCountsOnOccurrenceDate() throws {
        let fixture = try Fixture()
        let nextDay = try V0MigrationFixture.date("2026-09-23")
        let reviewedAt = fixture.now.addingTimeInterval(86400)
        _ = try fixture.review.approve(fixture.occurrence, submissionID: fixture.submissionID, at: reviewedAt)
        let original = try fixture.query.snapshot(for: fixture.date, at: reviewedAt)
        let current = try fixture.query.snapshot(for: nextDay, at: reviewedAt)
        #expect(original.completedCount == 1 && original.totalCount == 1 && original.isAllCompleted)
        #expect(
            original.tasks.first?.submission?.state == .approved
                && original.tasks.first?.completion?.source == .parentApproval)
        #expect(current.completedCount == 0 && current.totalCount == 0 && current.carryOverTasks.isEmpty)
    }

    @Test("坏等待状态、时长或审核元数据不能被查询静默当作普通 pending", arguments: [0, 1, 2])
    func queryRejectsCorruptWaitingFacts(kind: Int) throws {
        let fixture = try Fixture()
        if kind == 0 {
            fixture.occurrence.statusRawValue = TaskOccurrenceStatus.skipped.rawValue
        } else if kind == 1 {
            let timer = TimerSession(
                occurrenceID: fixture.occurrence.id, state: .ended,
                startedAt: fixture.now, lastResumedAt: fixture.now, accumulatedActiveSeconds: 1, endedAt: fixture.now)
            fixture.context.insert(timer)
            timer.occurrence = fixture.occurrence
        } else {
            let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
            row.reviewedAt = fixture.now
        }
        try fixture.context.save()
        #expect(throws: TaskSubmissionError.corruptHistory(fixture.occurrence.id)) {
            try fixture.query.item(id: fixture.occurrence.id, at: fixture.now)
        }
        #expect(!fixture.context.hasChanges)
    }

    @Test("坏等待在完整核对前拒绝，正常未来实例不被半更新")
    func corruptHistoryPreventsPartialReconciliation() throws {
        let fixture = try Fixture()
        let tomorrow = try V0MigrationFixture.date("2026-09-23")
        let ordinary = try fixture.makeOccurrence(date: tomorrow)
        let originalTime = ordinary.scheduledAt
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        row.reviewedAt = fixture.now
        fixture.template.title = "合成新模板"
        try fixture.context.save()
        let candidates = [fixture.date, tomorrow].map {
            ResolvedTaskCandidate(
                date: $0, scheduledAt: fixture.now.addingTimeInterval(7200), origin: .generated(templateRevision: 1))
        }
        #expect(throws: TaskSubmissionError.corruptHistory(fixture.occurrence.id)) {
            try TaskOccurrenceReconciliationService(context: fixture.context).reconcile(
                template: fixture.template,
                candidates: candidates, in: fixture.date...tomorrow, today: fixture.date, now: fixture.now)
        }
        #expect(ordinary.scheduledAt == originalTime && ordinary.titleSnapshot == "合成验收" && !fixture.context.hasChanges)
    }

    @Test("退回可调时，但旧提交只读快照不被当前调时重解释")
    func returnedOccurrenceCanRescheduleWithoutChangingOldSnapshot() throws {
        let fixture = try Fixture()
        _ = try fixture.review.returnForRevision(
            fixture.occurrence, submissionID: fixture.submissionID, at: fixture.now)
        try ParentTodayTaskManagementService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone
        )
        .reschedule(occurrenceID: fixture.occurrence.id, to: fixture.now.addingTimeInterval(-3600), at: fixture.now)
        let item = try fixture.query.item(id: fixture.occurrence.id, at: fixture.now)
        #expect(
            !item.isAwaitingReview && item.submission?.state == .returned && item.submission?.timing == .beforeReminder)
        #expect(item.submission?.expectedCoins == 10 && item.scheduledAt == fixture.now.addingTimeInterval(-3600))
    }

    @Test("磁盘重开后等待、退回和冲正历史保护与只读派生不丢失", arguments: [0, 1, 2])
    func protectionSurvivesDiskReopen(outcome: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let submissionID = try seedProtectionDisk(at: url, outcome: outcome)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            let occurrence = try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
            let date = try V0MigrationFixture.date("2026-09-22")
            let now = try V0MigrationFixture.instant("2026-09-22T10:30:02Z")
            let calendar = Calendar(identifier: .gregorian)
            let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            let item = try TodayTaskQueryService(context: context, calendar: calendar, timeZone: zone).item(
                id: occurrence.id, at: now)
            #expect(item.submission?.id == submissionID && item.isAwaitingReview == (outcome == 0))
            #expect(item.status == .pending && item.completion == nil)
            let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
            template.categoryRawValue = TaskCategory.challenge.rawValue
            template.timePeriodRawValue = TaskTimePeriod.evening.rawValue
            template.verificationTypeRawValue = TaskVerificationType.selfConfirm.rawValue
            template.xpReward = 41
            template.coinReward = 23
            template.activeBonusCoin = 9
            template.revision = 2
            try context.save()
            let updated = try TaskOccurrenceReconciliationService(context: context).reconcile(
                template: template,
                candidates: [
                    .init(
                        date: date, scheduledAt: now.addingTimeInterval(7200), origin: .generated(templateRevision: 2))
                ],
                in: date...date, today: date, now: now)
            #expect(updated.protectedCount == 1 && updated.updatedCount == 0)
            #expect(occurrence.categorySnapshot == .unassigned && occurrence.timePeriodSnapshot == .allDay)
            #expect(occurrence.verificationTypeSnapshot == .parentApproval && occurrence.sourceRevision == 1)
            #expect(
                occurrence.xpRewardSnapshot == 11 && occurrence.coinRewardSnapshot == 7
                    && occurrence.activeBonusCoinSnapshot == 3)
            #expect(throws: TaskGraphDeletionError.protectedHistory(occurrence.id)) {
                try TaskGraphDeletionService(context: context).stageOccurrenceDeletion(occurrence)
            }
            let report = try ParentCalendarDayService(context: context, calendar: calendar, timeZone: zone)
                .apply(.setHoliday, on: date, today: date, now: now)
            #expect(report.deletedCount == 0 && report.protectedCount == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
        }
    }

    @Test("无提交的自行确认完成冲正历史也不能从维护入口抹掉")
    func selfConfirmedAuditPreventsDeletionAfterUndo() throws {
        let context = ModelContext(try AppModelContainer.make(inMemory: true))
        context.autosaveEnabled = false
        let now = try V0MigrationFixture.instant("2026-09-22T10:30:00Z")
        let occurrence = TaskOccurrence(
            templateID: V0MigrationFixture.templateID,
            date: try V0MigrationFixture.date("2026-09-22"), scheduledAt: now,
            titleSnapshot: "合成自行确认", iconSnapshot: "book.fill", colorSnapshot: "reading",
            targetDurationSnapshot: 900, sourceRevision: 1, createdAt: now, updatedAt: now)
        context.insert(occurrence)
        try context.save()
        let complete = try TaskCompletionService(context: context).complete(occurrence, at: now, source: .childManual)
        _ = try TaskCompletionUndoService(context: context).undo(
            occurrence, completionID: complete.completionID, at: now.addingTimeInterval(1))
        #expect(throws: TaskGraphDeletionError.protectedHistory(occurrence.id)) {
            try TaskGraphDeletionService(context: context).stageOccurrenceDeletion(occurrence)
        }
        #expect(occurrence.status == .pending && !context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TaskSubmission>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 2)
    }

    @Test("坏等待在日期覆盖修改前拒绝，原放假覆盖不被半撤销")
    func invalidWaitingDoesNotPartiallyRemoveDayOverride() throws {
        let fixture = try Fixture()
        let service = ParentCalendarDayService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
        _ = try service.apply(.setHoliday, on: fixture.date, today: fixture.date, now: fixture.now)
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        row.reviewedAt = fixture.now
        try fixture.context.save()
        #expect(throws: TaskSubmissionError.corruptHistory(fixture.occurrence.id)) {
            try service.apply(.removeOverride, on: fixture.date, today: fixture.date, now: fixture.now)
        }
        let override = try #require(fixture.context.fetch(FetchDescriptor<DayOverride>()).first)
        #expect(override.dayType == .holiday && !fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 1)
    }

    private func seedProtectionDisk(at url: URL, outcome: Int) throws -> UUID {
        let fixture = try Fixture(storeURL: url)
        try fixture.applyOutcome(outcome)
        return fixture.submissionID
    }

    private final class Fixture {
        let context: ModelContext
        let template: TaskTemplate
        let occurrence: TaskOccurrence
        let date: LocalDate
        let now: Date
        let calendar = Calendar(identifier: .gregorian)
        let timeZone: TimeZone
        let submissionID: UUID
        var review: TaskSubmissionReviewService { TaskSubmissionReviewService(context: context) }
        var query: TodayTaskQueryService {
            TodayTaskQueryService(context: context, calendar: calendar, timeZone: timeZone)
        }

        init(storeURL: URL? = nil) throws {
            context = ModelContext(
                try storeURL.map { try AppModelContainer.make(storeURL: $0) } ?? AppModelContainer.make(inMemory: true))
            context.autosaveEnabled = false
            date = try V0MigrationFixture.date("2026-09-22")
            now = try V0MigrationFixture.instant("2026-09-22T10:30:00Z")
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            template = TaskTemplate(
                id: V0MigrationFixture.templateID, title: "合成验收", iconName: "book.fill", colorToken: "reading",
                targetDurationSeconds: 900, createdAt: now, updatedAt: now)
            let rule = ReminderRule(
                taskTemplateID: template.id, recurrence: .once(on: date), timeOfDayMinutes: 19 * 60 + 30)
            occurrence = TaskOccurrence(
                id: V0MigrationFixture.completedID, templateID: template.id, date: date,
                scheduledAt: now.addingTimeInterval(3600), titleSnapshot: template.title,
                iconSnapshot: template.iconName,
                colorSnapshot: template.colorToken, targetDurationSnapshot: 900, sourceRevision: 1,
                createdAt: now, updatedAt: now, verificationTypeSnapshot: .parentApproval,
                xpRewardSnapshot: 11, coinRewardSnapshot: 7, activeBonusCoinSnapshot: 3)
            context.insert(template)
            context.insert(rule)
            context.insert(occurrence)
            template.reminderRule = rule
            rule.taskTemplate = template
            occurrence.template = template
            try context.save()
            submissionID = try TaskSubmissionService(context: context).submit(occurrence, at: now).submissionID
        }

        func makeOccurrence(date: LocalDate) throws -> TaskOccurrence {
            let row = TaskOccurrence(
                templateID: template.id, date: date, scheduledAt: now.addingTimeInterval(3600),
                titleSnapshot: template.title, iconSnapshot: template.iconName, colorSnapshot: template.colorToken,
                targetDurationSnapshot: 900, sourceRevision: 1, createdAt: now, updatedAt: now)
            context.insert(row)
            row.template = template
            try context.save()
            return row
        }

        func makeOtherTemplateOccurrence() throws -> TaskOccurrence {
            let row = TaskOccurrence(
                templateID: V0MigrationFixture.orphanID, date: date, scheduledAt: now.addingTimeInterval(7200),
                titleSnapshot: "合成普通任务", iconSnapshot: "book.fill", colorSnapshot: "reading",
                targetDurationSnapshot: 900, sourceRevision: 1, createdAt: now, updatedAt: now)
            context.insert(row)
            try context.save()
            return row
        }

        func applyOutcome(_ outcome: Int) throws {
            if outcome == 1 {
                _ = try review.returnForRevision(occurrence, submissionID: submissionID, at: now)
            } else if outcome == 2 {
                let approved = try review.approve(occurrence, submissionID: submissionID, at: now)
                _ = try TaskCompletionUndoService(context: context).undo(
                    occurrence, completionID: try #require(approved.completionID), at: now.addingTimeInterval(1))
            }
        }
    }
}
