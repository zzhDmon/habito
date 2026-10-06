import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("通知业务重建")
@MainActor
struct NotificationRebuildServiceTests {
    @Test("等待清理时读取/取消/已送达读删失败，映射保留可追溯，下次成功再清理", arguments: [0, 1, 2, 3])
    func waitingCleanupFailuresRemainTraceable(kind: Int) async throws {
        let (fixture, occurrence) = try await approvalSetup()
        _ = try await snoozeService(fixture).schedule(occurrenceID: occurrence.id, at: fixture.now)
        let identifiers = Set(
            [NotificationKind.primary, .snooze].map {
                NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: $0).rawValue
            })
        fixture.scheduler.delivered = identifiers
        _ = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        if kind == 0 { fixture.scheduler.readFails = true }
        if kind == 1 { fixture.scheduler.pendingRemovalFails = true }
        if kind == 2 { fixture.scheduler.deliveredReadFails = true }
        if kind == 3 { fixture.scheduler.deliveredRemovalFails = true }
        let failed = try await fixture.service.rebuild(at: fixture.now.addingTimeInterval(1))
        #expect(!failed.reconciliation.isSuccessful)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: occurrence.id).count == 2)
        let settings = try #require(fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.lastNotificationSchedulingAt == fixture.now)
        fixture.scheduler.readFails = false
        fixture.scheduler.pendingRemovalFails = false
        fixture.scheduler.deliveredReadFails = false
        fixture.scheduler.deliveredRemovalFails = false
        let recovered = try await fixture.service.rebuild(at: fixture.now.addingTimeInterval(2))
        #expect(recovered.reconciliation.isSuccessful)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: occurrence.id).isEmpty)
        for identifier in identifiers {
            #expect(fixture.scheduler.pending[identifier] == nil && !fixture.scheduler.delivered.contains(identifier))
        }
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
    }

    @Test("多次系统等待依次提交与退回/重提，最终等待事实不能留下旧提醒", arguments: [false, true])
    func multipleBusinessChangesUseFinalFacts(resubmit: Bool) async throws {
        let (fixture, occurrence) = try await approvalSetup()
        _ = try await snoozeService(fixture).schedule(occurrenceID: occurrence.id, at: fixture.now)
        let primary = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        let snooze = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .snooze).rawValue
        fixture.scheduler.pending[primary] = nil
        fixture.scheduler.onReadAsync = {
            let row = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
            fixture.scheduler.onAdd = { _ in
                _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
                    occurrence, submissionID: row.submissionID, at: fixture.now)
                if resubmit {
                    _ = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
                }
            }
        }
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.isSuccessful)
        #expect((fixture.scheduler.pending[primary] != nil) == !resubmit)
        #expect(fixture.scheduler.pending[snooze] == nil)
        let history = TaskSubmissionHistory(context: fixture.context)
        #expect(try history.records(for: occurrence.id).count == (resubmit ? 2 : 1))
        #expect(try history.latest(for: occurrence)?.reviewState == (resubmit ? .waiting : .returned))
    }

    @Test("坏等待审计在系统操作前明确拒绝，旧卡片点击安全回首页")
    func corruptWaitingFailsWithoutSystemMutation() async throws {
        let (fixture, occurrence) = try await approvalSetup()
        let row = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        let latest = try TaskSubmissionHistory(context: fixture.context).latest(for: occurrence)
        let record = try #require(latest)
        record.reviewStateRawValue = "corrupt"
        try fixture.context.save()
        let requests = fixture.scheduler.pending
        let addCount = fixture.scheduler.addCount
        await #expect(throws: TaskSubmissionError.corruptHistory(occurrence.id)) {
            _ = try await fixture.service.rebuild(at: fixture.now)
        }
        #expect(fixture.scheduler.pending == requests && fixture.scheduler.addCount == addCount)
        let identifier = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        #expect(NotificationNavigationService(context: fixture.context).destination(for: identifier) == .home)
        #expect(record.id == row.submissionID)
    }

    @Test("等待/退回旧稍后/退回新稍后真实磁盘重开，按事实恢复且不补奖", arguments: [0, 1, 2])
    func diskRestartRespectsWaitingAndSnoozeEpoch(outcome: Int) async throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let (occurrenceID, submissionID) = try await seedApprovalNotifications(at: url, outcome: outcome)
        for _ in 0..<2 {
            let fixture = try Fixture(storeURL: url)
            let occurrence = try #require(
                fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.id == occurrenceID })
            let result = try await fixture.service.rebuild(at: fixture.now)
            let primary = NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: .primary).rawValue
            let snooze = NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: .snooze).rawValue
            #expect(result.reconciliation.isSuccessful)
            #expect((fixture.scheduler.pending[primary] != nil) == (outcome != 0))
            #expect((fixture.scheduler.pending[snooze] != nil) == (outcome == 2))
            let link = try NotificationLinkStore(context: fixture.context).link(requestIdentifier: snooze)
            #expect(link?.submissionIDAtScheduling == (outcome == 2 ? submissionID : nil))
            #expect(try TaskSubmissionHistory(context: fixture.context).latest(for: occurrence)?.id == submissionID)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            #expect(
                try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        }
    }

    @Test("提交等待清理两种提醒和已送达卡片，旧点击安全回家；通过才到账", arguments: [false, true])
    func waitingAndApprovalCleanNotificationsWithoutPrematureRewards(zero: Bool) async throws {
        let (fixture, occurrence) = try await approvalSetup(zero: zero)
        _ = try await snoozeService(fixture).schedule(occurrenceID: occurrence.id, at: fixture.now)
        let identifiers = Set(
            [NotificationKind.primary, .snooze].map {
                NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: $0).rawValue
            })
        fixture.scheduler.delivered = identifiers
        let submission = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        let navigation = NotificationNavigationService(context: fixture.context)
        for identifier in identifiers { #expect(navigation.destination(for: identifier) == .home) }
        let waiting = try await fixture.service.rebuild(at: fixture.now)
        #expect(waiting.reconciliation.isSuccessful && waiting.scheduledSnoozeCount == 0)
        for identifier in identifiers { #expect(fixture.scheduler.pending[identifier] == nil) }
        #expect(fixture.scheduler.delivered.isEmpty)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: occurrence.id).isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        let review = TaskSubmissionReviewService(context: fixture.context)
        _ = try review.approve(occurrence, submissionID: submission.submissionID, at: fixture.now)
        let approved = try await fixture.service.rebuild(at: fixture.now)
        #expect(approved.reconciliation.isSuccessful && occurrence.status == .completed)
        #expect(
            try RewardLedgerService(context: fixture.context).balance()
                == RewardBalance(effectiveXP: zero ? 0 : 11, coins: zero ? 0 : 10))
        let repeated = try review.approve(occurrence, submissionID: submission.submissionID, at: fixture.now)
        #expect(!repeated.didReview)
        let addCount = fixture.scheduler.addCount
        _ = try await fixture.service.rebuild(at: fixture.now)
        #expect(fixture.scheduler.addCount == addCount)
        for identifier in identifiers { #expect(navigation.destination(for: identifier) == .home) }
    }

    @Test("退回只恢复未来主提醒，到点/过期/跨日不补发，也不恢复提交前稍后", arguments: [0, 1, 2, 3])
    func returnOnlyRestoresFuturePrimary(boundary: Int) async throws {
        let (fixture, occurrence) = try await approvalSetup()
        _ = try await snoozeService(fixture).schedule(occurrenceID: occurrence.id, at: fixture.now)
        let primary = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        let snooze = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .snooze).rawValue
        fixture.scheduler.delivered = [primary, snooze]
        let submission = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        let returnedAt: Date =
            switch boundary {
            case 0: fixture.now
            case 1: occurrence.scheduledAt
            case 2: occurrence.scheduledAt.addingTimeInterval(1)
            default: fixture.now.addingTimeInterval(86400)
            }
        _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
            occurrence, submissionID: submission.submissionID, at: returnedAt)
        let rebuilt = try await fixture.service.rebuild(at: returnedAt)
        #expect(rebuilt.reconciliation.isSuccessful)
        #expect((fixture.scheduler.pending[primary] != nil) == (boundary == 0))
        #expect(fixture.scheduler.pending[snooze] == nil)
        #expect(!fixture.scheduler.delivered.contains(snooze))
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: snooze) == nil)
        #expect(occurrence.status == .pending && occurrence.completionRecord == nil)
        #expect(try TaskSubmissionHistory(context: fixture.context).records(for: occurrence.id).count == 1)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
        _ = try await fixture.service.rebuild(at: returnedAt)
        #expect(fixture.scheduler.pending[snooze] == nil)
    }

    @Test("同一时刻多轮提交退回，旧稍后不复活；退回后明确新稍后在重建中保留世代")
    func fastReturnsRejectOldSnoozeButKeepExplicitNewEpoch() async throws {
        let (fixture, occurrence) = try await approvalSetup()
        let snooze = snoozeService(fixture)
        let store = NotificationLinkStore(context: fixture.context)
        let identifier = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .snooze).rawValue
        _ = try await snooze.schedule(occurrenceID: occurrence.id, at: fixture.now)
        #expect(try store.link(requestIdentifier: identifier)?.submissionIDAtScheduling == nil)
        for _ in 0..<2 {
            let row = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
            _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
                occurrence, submissionID: row.submissionID, at: fixture.now)
            _ = try await fixture.service.rebuild(at: fixture.now)
            #expect(fixture.scheduler.pending[identifier] == nil)
            _ = try await snooze.schedule(occurrenceID: occurrence.id, at: fixture.now)
            for _ in 0..<3 {
                let result = try await fixture.service.rebuild(at: fixture.now)
                #expect(result.reconciliation.isSuccessful && result.scheduledSnoozeCount == 1)
                let savedLink = try store.link(requestIdentifier: identifier)
                let link = try #require(savedLink)
                #expect(link.submissionIDAtScheduling == row.submissionID && link.createdAt == fixture.now)
                #expect(link.scheduledAt == fixture.now.addingTimeInterval(600))
            }
        }
        #expect(try TaskSubmissionHistory(context: fixture.context).records(for: occurrence.id).count == 2)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
    }

    @Test("系统读取或添加等待期间提交/通过/退回，最终队列按最新事实稳定", arguments: [false, true], [0, 1, 2])
    func reviewDuringSystemAwaitUsesLatestFacts(duringAdding: Bool, outcome: Int) async throws {
        let (fixture, occurrence) = try await approvalSetup()
        _ = try await snoozeService(fixture).schedule(occurrenceID: occurrence.id, at: fixture.now)
        let primary = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        let snooze = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .snooze).rawValue
        let change = {
            let row = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
            let review = TaskSubmissionReviewService(context: fixture.context)
            if outcome == 1 { _ = try review.approve(occurrence, submissionID: row.submissionID, at: fixture.now) }
            if outcome == 2 {
                _ = try review.returnForRevision(occurrence, submissionID: row.submissionID, at: fixture.now)
            }
        }
        if duringAdding {
            fixture.scheduler.pending[primary] = nil
            fixture.scheduler.onAdd = { _ in try change() }
        } else {
            fixture.scheduler.onReadAsync = { try change() }
        }
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.isSuccessful)
        #expect((fixture.scheduler.pending[primary] != nil) == (outcome == 2))
        #expect(fixture.scheduler.pending[snooze] == nil)
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: snooze) == nil)
        #expect(
            try RewardLedgerService(context: fixture.context).balance()
                == RewardBalance(effectiveXP: outcome == 1 ? 11 : 0, coins: outcome == 1 ? 10 : 0))
        #expect(try TaskSubmissionHistory(context: fixture.context).records(for: occurrence.id).count == 1)
    }

    @Test("新完成清理两种提醒，审计撤销仅恢复未过期主提醒", arguments: [false, true])
    func auditedUndoRestoresOnlyFuturePrimary(afterReminder: Bool) async throws {
        let fixture = try Fixture()
        let template = try fixture.insertDailyTemplate()
        template.xpReward = 11
        template.coinReward = 7
        template.activeBonusCoin = 3
        try fixture.context.save()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" })
        let primary = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        let snooze = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .snooze).rawValue
        _ = try await TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler, permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone
        ).schedule(occurrenceID: occurrence.id, at: fixture.now)
        fixture.scheduler.delivered = [primary, snooze]
        let completedAt = afterReminder ? occurrence.scheduledAt.addingTimeInterval(1) : fixture.now
        let trigger = NotificationRebuildTrigger()
        let model = TaskSessionViewModel(
            occurrenceID: occurrence.id, context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone, dateProvider: FixedDateProvider(value: completedAt),
            notificationRebuildTrigger: trigger)
        model.load()
        model.completeTask()
        #expect(trigger.revision == 1 && occurrence.status == .completed)
        let result = try await fixture.service.rebuild(at: completedAt)
        #expect(result.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending[primary] == nil && fixture.scheduler.pending[snooze] == nil)
        #expect(fixture.scheduler.delivered.isEmpty)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: occurrence.id).isEmpty)
        let undoAt = completedAt.addingTimeInterval(1)
        let undoModel = TaskSessionViewModel(
            occurrenceID: occurrence.id, context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone, dateProvider: FixedDateProvider(value: undoAt),
            notificationRebuildTrigger: trigger)
        undoModel.load()
        undoModel.undoCompletion()
        #expect(trigger.revision == 2 && occurrence.status == .pending)
        let restored = try await fixture.service.rebuild(at: undoAt)
        #expect(restored.reconciliation.isSuccessful)
        #expect((fixture.scheduler.pending[primary] != nil) == !afterReminder)
        #expect(fixture.scheduler.pending[snooze] == nil && fixture.scheduler.delivered.isEmpty)
        let record = try #require(fixture.context.fetch(FetchDescriptor<CompletionRecord>()).first)
        #expect(record.revokedAt == undoAt && record.rewardSettlementVersion == 1)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
    }

    @Test("提前开始后清理主提醒，但已安排的稍后槽位仍按进行中规则保留")
    func startingTaskClearsPrimaryAndPreservesEligibleSnooze() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" })
        let primary = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        let snooze = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .snooze).rawValue
        _ = try await TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler, permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone, operationGate: fixture.operationGate
        ).schedule(occurrenceID: occurrence.id, at: fixture.now)
        let trigger = NotificationRebuildTrigger()
        let model = TaskSessionViewModel(
            occurrenceID: occurrence.id, context: fixture.context, calendar: fixture.calendar,
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now), notificationRebuildTrigger: trigger)
        model.load()
        model.startOrResume()
        #expect(trigger.revision == 1)
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending[primary] == nil)
        #expect(fixture.scheduler.pending[snooze] != nil)
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: primary) == nil)
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: snooze) != nil)
        #expect(result.selection.primaryCandidates.count == 14)
        #expect(result.scheduledSnoozeCount == 1)
        #expect(occurrence.status == .inProgress)
    }

    @Test("时区重建更新未来实例与稳定通知映射，不改写完成绝对时间")
    func changedTimeZoneRebuildsFutureRequestsAndPreservesCompletion() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrences = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())
        let completed = try #require(occurrences.first { $0.dateKey == "2026-09-27" })
        let future = try #require(occurrences.first { $0.dateKey == "2026-09-28" })
        let completedScheduledAt = completed.scheduledAt
        let record = try TaskProgressService(context: fixture.context).complete(
            completed, at: fixture.now, source: .childManual)
        let futureID = future.id
        let identifier = NotificationRequestIdentifier(occurrenceID: futureID, kind: .primary).rawValue
        let oldScheduledAt = future.scheduledAt
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let shifted = NotificationRebuildService(
            context: fixture.context, scheduler: fixture.scheduler, permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: timeZone, operationGate: fixture.operationGate)
        let result = try await shifted.rebuild(at: fixture.now)
        let expected = try Date("2026-09-29T02:30:00Z", strategy: .iso8601)
        #expect(result.reconciliation.isSuccessful)
        #expect(future.id == futureID)
        #expect(future.scheduledAt == expected)
        #expect(future.scheduledAt != oldScheduledAt)
        #expect(fixture.scheduler.pending[identifier]?.scheduledAt == expected)
        #expect(
            try NotificationLinkStore(context: fixture.context).link(requestIdentifier: identifier)?.scheduledAt
                == expected)
        #expect(completed.status == .completed)
        #expect(completed.scheduledAt == completedScheduledAt)
        #expect(record.completedAt == fixture.now)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
    }

    @Test("预算恰好覆盖最低日期整天时，重建保存完整边界且连续核对不重复添加")
    func exactDailyBudgetPersistsCompleteMinimumCoverage() async throws {
        let fixture = try Fixture()
        for _ in 0..<6 { _ = try fixture.insertDailyTemplate() }
        let result = try await fixture.service.rebuild(at: fixture.now)
        let boundary = try LocalDate(dateKey: "2026-10-04")
        #expect(result.reconciliation.isSuccessful)
        #expect(result.selection.primaryCandidates.count == 48)
        #expect(result.selection.coverageThrough == boundary)
        #expect(!result.selection.isCoverageBoundaryPartial)
        #expect(result.selection.hasMinimumCoverage)
        let settings = try #require(fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.schedulingHorizonDateKey == boundary.dateKey)
        #expect(fixture.scheduler.pending.count == 48)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 48)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 90)
        let identifiers = Set(fixture.scheduler.pending.keys)
        let addCount = fixture.scheduler.addCount
        let repeated = try await fixture.service.rebuild(at: fixture.now)
        #expect(repeated.selection == result.selection)
        #expect(repeated.reconciliation.retainedIdentifiers.count == 48)
        #expect(fixture.scheduler.addCount == addCount)
        #expect(Set(fixture.scheduler.pending.keys) == identifiers)
    }

    @Test("系统添加期间停用模板并删除未来实例，旧主提醒不残留")
    func disablingTemplateDuringAddingCleansDeletedOccurrences() async throws {
        let fixture = try Fixture()
        let template = try fixture.insertDailyTemplate()
        fixture.scheduler.onAdd = { _ in
            _ = try TaskTemplateLifecycleService(
                context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone
            ).perform(
                templateID: template.id, action: .disable,
                today: LocalDate(dateKey: "2026-09-27"), now: fixture.now)
        }
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.isSuccessful)
        #expect(result.selection.primaryCandidates.isEmpty)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        #expect(template.lifecycleState == .disabled)
    }

    @Test("48 主提醒与 8 稍后槽位满额时，等待期间完成任务会补齐新候选而不超预算")
    func changedBusinessRefillsPrimaryBudgetWithoutDroppingSnoozes() async throws {
        let fixture = try Fixture()
        for _ in 0..<8 { _ = try fixture.insertDailyTemplate() }
        _ = try await fixture.service.rebuild(at: fixture.now)
        let today = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).filter { $0.dateKey == "2026-09-27" }
        let snooze = TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler, permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone, operationGate: fixture.operationGate)
        for occurrence in today {
            _ = try await snooze.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        #expect(fixture.scheduler.pending.count == 56)
        let completed = try #require(today.first)
        let before = Set(fixture.scheduler.pending.keys)
        fixture.scheduler.onReadAsync = {
            _ = try TaskProgressService(context: fixture.context).complete(
                completed, at: fixture.now, source: .childManual)
        }
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.isSuccessful)
        #expect(result.selection.primaryCandidates.count == 48)
        #expect(result.scheduledSnoozeCount == 7)
        #expect(fixture.scheduler.pending.count == 55)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: completed.id).isEmpty)
        #expect(Set(fixture.scheduler.pending.keys).subtracting(before).count == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 55)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 120)
    }

    @Test("读取系统队列期间完成任务，返回成功前清理旧主提醒")
    func completionDuringQueueReadCannotRetainOldPrimary() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" })
        let identifier = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        fixture.scheduler.onReadAsync = {
            _ = try TaskProgressService(context: fixture.context).complete(
                occurrence, at: fixture.now, source: .childManual)
        }
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending[identifier] == nil)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: occurrence.id).isEmpty)
        #expect(result.selection.primaryCandidates.count == 14)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
    }

    @Test("读取系统队列期间改单日时间，最终系统请求与映射使用新快照")
    func rescheduleDuringQueueReadUsesLatestSnapshot() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" })
        let identifier = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        let newTime = occurrence.scheduledAt.addingTimeInterval(30 * 60)
        fixture.scheduler.onReadAsync = {
            try ParentTodayTaskManagementService(
                context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone
            ).reschedule(occurrenceID: occurrence.id, to: newTime, at: fixture.now)
        }
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending[identifier]?.scheduledAt == newTime)
        #expect(
            try NotificationLinkStore(context: fixture.context).link(requestIdentifier: identifier)?.scheduledAt
                == newTime)
        #expect(result.selection.primaryCandidates.first { $0.occurrenceID == occurrence.id }?.scheduledAt == newTime)
        #expect(fixture.scheduler.pending.count == 15)
    }

    @Test("系统添加主提醒期间完成任务，不落成功的过期映射")
    func completionDuringAddingCannotResurrectNotification() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        var completedID: UUID?
        fixture.scheduler.onAdd = { request in
            let occurrence = try #require(
                fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.id == request.occurrenceID })
            completedID = occurrence.id
            _ = try TaskProgressService(context: fixture.context).complete(
                occurrence, at: fixture.now, source: .childManual)
        }
        let result = try await fixture.service.rebuild(at: fixture.now)
        let occurrenceID = try #require(completedID)
        let identifier = NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: .primary).rawValue
        #expect(result.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending[identifier] == nil)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: occurrenceID).isEmpty)
        #expect(fixture.scheduler.pending.count == 14)
    }

    @Test("系统添加期间撤销授权，最终清空旧请求且不写排程成功日期")
    func revocationDuringAddingCannotPersistAuthorizedCheckpoint() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        fixture.scheduler.onAdd = { _ in fixture.permissions.currentAuthorizationState = .denied }
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.authorization == .denied)
        #expect(result.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        let settings = try #require(fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.lastNotificationSchedulingAt == nil)
        #expect(settings.schedulingHorizonDateKey == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 15)
    }

    @Test("跨午夜清理昨日稍后与已送达卡片，不改写完成历史")
    func midnightRebuildClearsYesterdaySnoozeAndPreservesHistory() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let today = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).filter { $0.dateKey == "2026-09-27" }
        let snoozed = try #require(today.first)
        let completed = try #require(today.first { $0.id != snoozed.id })
        _ = try await TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler, permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone
        ).schedule(occurrenceID: snoozed.id, at: fixture.now)
        _ = try TaskProgressService(context: fixture.context).complete(completed, at: fixture.now, source: .childManual)
        let primaryIdentifier = NotificationRequestIdentifier(occurrenceID: snoozed.id, kind: .primary).rawValue
        let snoozeIdentifier = NotificationRequestIdentifier(occurrenceID: snoozed.id, kind: .snooze).rawValue
        fixture.scheduler.delivered = [primaryIdentifier, snoozeIdentifier]
        let tomorrow = try Date("2026-09-27T16:00:01Z", strategy: .iso8601)
        let result = try await fixture.service.rebuild(at: tomorrow)
        #expect(result.reconciliation.isSuccessful)
        #expect(result.scheduledSnoozeCount == 0)
        #expect(fixture.scheduler.pending[primaryIdentifier] == nil)
        #expect(fixture.scheduler.pending[snoozeIdentifier] == nil)
        #expect(fixture.scheduler.delivered.isEmpty)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: snoozed.id).isEmpty)
        #expect(completed.status == .completed)
        #expect(completed.dateKey == "2026-09-27")
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        let identifiers = Set(fixture.scheduler.pending.keys)
        _ = try await fixture.service.rebuild(at: tomorrow)
        #expect(Set(fixture.scheduler.pending.keys) == identifiers)
    }

    @Test("等待系统队列时取消旧重建，不写成功检查点，后续重建可继续")
    func cancelledRebuildDoesNotPersistStaleCheckpoint() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        let entered = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        fixture.scheduler.onReadAsync = {
            entered.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        let rebuilding = Task {
            do {
                _ = try await fixture.service.rebuild(at: fixture.now)
                return false
            } catch is CancellationError {
                return true
            }
        }
        var iterator = entered.stream.makeAsyncIterator()
        _ = await iterator.next()
        rebuilding.cancel()
        release.continuation.yield(())
        #expect(try await rebuilding.value)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
        // 实例物化已独立保存；取消排程并不删除仍可手动完成的业务任务。
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 15)
        let retried = try await fixture.service.rebuild(at: fixture.now)
        #expect(retried.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending.count == 15)
    }

    @Test("磁盘重开后从映射恢复稍后提醒与主提醒，重复重建不新增")
    func diskReopenRestoresStableSnoozeSlot() async throws {
        let directory = URL.temporaryDirectory.appending(
            path: "Habito-M4-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // SwiftData 在 iPadOS 17 延迟释放 SQLite 连接；不能在重开后立即 unlink。
        // 使用测试沙箱随机临时目录，由沙箱清理，绝不触碰正式库。
        let storeURL = directory.appending(path: "Habito-M4.store")
        let (occurrenceID, scheduledAt) = try await seedNotifications(storeURL: storeURL)
        let reopened = try Fixture(storeURL: storeURL)
        let restored = try await reopened.service.rebuild(at: reopened.now)
        let identifier = NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: .snooze).rawValue
        #expect(restored.reconciliation.isSuccessful)
        #expect(restored.scheduledSnoozeCount == 1)
        #expect(reopened.scheduler.pending.count == 16)
        #expect(reopened.scheduler.pending[identifier]?.scheduledAt == scheduledAt)
        #expect(try reopened.context.fetchCount(FetchDescriptor<NotificationLink>()) == 16)
        let repeated = try await reopened.service.rebuild(at: reopened.now)
        #expect(repeated.reconciliation.addedIdentifiers.isEmpty)
        #expect(repeated.reconciliation.retainedIdentifiers.count == 16)
    }

    @Test("拒绝通知仍生成任务但不伪造排程检查点，重新授权可恢复")
    func deniedAuthorizationPreservesManualTasksAndCanRecover() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        fixture.permissions.currentAuthorizationState = .denied
        let denied = try await fixture.service.rebuild(at: fixture.now)
        #expect(denied.authorization == .denied)
        #expect(denied.reconciliation.isSuccessful)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 15)
        let settings = try #require(fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.lastNotificationSchedulingAt == nil)
        #expect(settings.schedulingHorizonDateKey == nil)
        #expect(fixture.permissions.requestCount == 0)

        fixture.permissions.currentAuthorizationState = .authorized
        let restored = try await fixture.service.rebuild(at: fixture.now)
        #expect(restored.reconciliation.addedIdentifiers.count == 15)
        #expect(fixture.scheduler.pending.count == 15)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 15)
        #expect(settings.lastNotificationSchedulingAt == fixture.now)
    }

    @Test("关闭通知清理旧排程，不丢失完成历史与手动任务")
    func revokingAuthorizationCleansRequestsWithoutLosingProgress() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        _ = try TaskProgressService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        fixture.permissions.currentAuthorizationState = .denied
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.removedIdentifiers.count == 15)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 15)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1)
        #expect(occurrence.status == .completed)
    }

    @Test("系统单条失败不覆盖成功检查点，家长诊断可发起重试")
    func partialFailureExposesRetryAndPreservesCheckpoint() async throws {
        let fixture = try Fixture()
        let template = try fixture.insertDailyTemplate()
        let success = try await fixture.service.rebuild(at: fixture.now)
        let trigger = NotificationRebuildTrigger()
        let model = ParentNotificationDiagnosticsViewModel(
            service: NotificationPermissionService(context: fixture.context, provider: fixture.permissions),
            rebuildTrigger: trigger
        )
        #expect(model.schedulingState == .idle)
        trigger.recordStarted()
        #expect(model.schedulingState == .rebuilding)
        trigger.record(success, checkedAt: fixture.now)
        #expect(model.schedulingState == .completed(success, checkedAt: fixture.now))

        template.title = "修改后的阅读"
        try fixture.context.save()
        fixture.scheduler.addFails = true
        let later = fixture.now.addingTimeInterval(60)
        let failed = try await fixture.service.rebuild(at: later)
        #expect(!failed.reconciliation.isSuccessful)
        trigger.record(failed, checkedAt: later)
        #expect(model.schedulingState == .failed)
        let settings = try #require(fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.lastNotificationSchedulingAt == fixture.now)
        model.retryScheduling()
        #expect(trigger.revision == 1)
        fixture.scheduler.addFails = false
        let retried = try await fixture.service.rebuild(at: later)
        trigger.record(retried, checkedAt: later)
        #expect(model.schedulingState == .completed(retried, checkedAt: later))
        #expect(settings.lastNotificationSchedulingAt == later)
    }

    @Test("连续五次重建仅首次添加且记录覆盖检查点")
    func fiveRebuildsAreIdempotent() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()

        var results: [NotificationRebuildResult] = []
        for _ in 0..<5 {
            results.append(try await fixture.service.rebuild(at: fixture.now))
        }

        #expect(fixture.scheduler.addCount == 15)
        #expect(fixture.scheduler.pending.count == 15)
        #expect(results[0].reconciliation.addedIdentifiers.count == 15)
        #expect(
            results.dropFirst().allSatisfy {
                $0.reconciliation.retainedIdentifiers.count == 15
                    && $0.reconciliation.addedIdentifiers.isEmpty
                    && $0.reconciliation.replacedIdentifiers.isEmpty
                    && $0.reconciliation.removedIdentifiers.isEmpty
            }
        )
        #expect(results.allSatisfy { $0.selection.hasMinimumCoverage })
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 15)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 15)

        let settings = try #require(fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.lastInstanceGenerationAt == fixture.now)
        #expect(settings.lastNotificationSchedulingAt == fixture.now)
        #expect(settings.schedulingHorizonDateKey == "2026-10-11")
    }

    @Test("通知物化传播独立可空时间，五次重建仍只使用提醒", arguments: [0, 1, 2])
    func rebuildPropagatesTimesWithoutChangingNotification(kind: Int) async throws {
        let fixture = try Fixture()
        fixture.context.autosaveEnabled = false
        let template = try fixture.insertDailyTemplate()
        let rule = try #require(template.reminderRule)
        rule.plannedTimeOfDayMinutes = kind == 0 ? nil : 22 * 60
        rule.deadlineTimeOfDayMinutes = kind == 1 ? 8 * 60 : nil
        try fixture.context.save()
        var ids: Set<UUID> = []
        for iteration in 0..<5 {
            let result = try await fixture.service.rebuild(at: fixture.now)
            #expect(result.reconciliation.isSuccessful)
            let rows = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())
            #expect(rows.count == 15)
            if iteration == 0 { ids = Set(rows.map(\.id)) }
            #expect(Set(rows.map(\.id)) == ids)
            for row in rows {
                #expect(row.plannedAt == (kind == 0 ? nil : try Date("\(row.dateKey)T14:00:00Z", strategy: .iso8601)))
                #expect(row.deadlineAt == (kind == 1 ? try Date("\(row.dateKey)T00:00:00Z", strategy: .iso8601) : nil))
                let identifier = NotificationRequestIdentifier(occurrenceID: row.id, kind: .primary).rawValue
                #expect(fixture.scheduler.pending[identifier]?.scheduledAt == row.scheduledAt)
                #expect(row.scheduledAt == (try Date("\(row.dateKey)T11:30:00Z", strategy: .iso8601)))
            }
        }
        #expect(fixture.scheduler.addCount == 15)
        let originalRequests = fixture.scheduler.pending
        rule.plannedTimeOfDayMinutes = nil
        rule.deadlineTimeOfDayMinutes = nil
        try fixture.context.save()
        let cleared = try await fixture.service.rebuild(at: fixture.now)
        #expect(cleared.reconciliation.isSuccessful && fixture.scheduler.pending == originalRequests)
        #expect(fixture.scheduler.addCount == 15)
        #expect(
            try fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).allSatisfy {
                $0.plannedAt == nil && $0.deadlineAt == nil
            })
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }

    @Test("通知重建保留单日时间快照，不从后改模板覆盖")
    func rebuildKeepsDetachedTimeSnapshots() async throws {
        let fixture = try Fixture()
        fixture.context.autosaveEnabled = false
        let template = try fixture.insertDailyTemplate()
        let rule = try #require(template.reminderRule)
        rule.plannedTimeOfDayMinutes = 18 * 60
        rule.deadlineTimeOfDayMinutes = 22 * 60
        try fixture.context.save()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let row = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" })
        let id = row.id
        row.isDetachedOverride = true
        row.plannedAt = nil
        row.deadlineAt = fixture.now.addingTimeInterval(600)
        let originalDeadline = row.deadlineAt
        try fixture.context.save()
        rule.plannedTimeOfDayMinutes = 8 * 60
        rule.deadlineTimeOfDayMinutes = nil
        template.revision = 2
        try fixture.context.save()
        _ = try await fixture.service.rebuild(at: fixture.now)
        #expect(row.id == id && row.isDetachedOverride && row.plannedAt == nil && row.deadlineAt == originalDeadline)
        let identifier = NotificationRequestIdentifier(occurrenceID: id, kind: .primary).rawValue
        #expect(fixture.scheduler.pending[identifier]?.scheduledAt == row.scheduledAt)
    }

    @Test("坏计划分钟让通知重建在物化前失败，不新增请求或半写实例")
    func invalidOptionalTimeCannotPartiallyMaterializeNotifications() async throws {
        let fixture = try Fixture()
        let template = try fixture.insertDailyTemplate()
        let rule = try #require(template.reminderRule)
        rule.plannedTimeOfDayMinutes = 1440
        try fixture.context.save()
        await #expect(
            throws: TaskRecurrenceExpansionError.invalidOptionalTimeOfDayMinutes(
                field: "plannedTimeOfDayMinutes", value: 1440)
        ) {
            try await fixture.service.rebuild(at: fixture.now)
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        #expect(fixture.scheduler.addCount == 0 && fixture.scheduler.pending.isEmpty && !fixture.context.hasChanges)
    }

    @Test("放假过滤实例，完成与停用后清理系统请求和映射")
    func holidayCompletionAndDisableCleanNotifications() async throws {
        let fixture = try Fixture()
        let template = try fixture.insertDailyTemplate()
        let holiday = try LocalDate(dateKey: "2026-09-28")
        fixture.context.insert(DayOverride(date: holiday, dayType: .holiday, updatedAt: fixture.now))
        try fixture.context.save()

        let first = try await fixture.service.rebuild(at: fixture.now)
        let occurrences = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())

        #expect(first.reconciliation.addedIdentifiers.count == 14)
        #expect(!occurrences.contains { $0.dateKey == holiday.dateKey })

        let completed = try #require(
            occurrences.first { $0.dateKey == "2026-09-27" }
        )
        _ = try TaskProgressService(context: fixture.context).complete(
            completed,
            at: fixture.now,
            source: .childManual
        )
        let today = try LocalDate(dateKey: "2026-09-27")
        _ = try TaskTemplateLifecycleService(
            context: fixture.context,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone
        ).perform(
            templateID: template.id,
            action: .disable,
            today: today,
            now: fixture.now
        )

        let second = try await fixture.service.rebuild(at: fixture.now)

        #expect(second.selection.primaryCandidates.isEmpty)
        #expect(second.reconciliation.removedIdentifiers.count == 14)
        #expect(fixture.scheduler.pending.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
        let remaining = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == completed.id)
        #expect(remaining.first?.status == .completed)
    }

    @Test("完成任务后重建会同时清理主提醒和稍后提醒")
    func completionCleansPrimaryAndSnoozeNotifications() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first {
                $0.dateKey == "2026-09-27"
            }
        )
        let snoozeService = TaskSnoozeService(
            context: fixture.context,
            scheduler: fixture.scheduler,
            permissionProvider: fixture.permissions,
            calendar: fixture.calendar,
            timeZone: fixture.timeZone
        )
        _ = try await snoozeService.schedule(occurrenceID: occurrence.id, at: fixture.now)

        let snoozeIdentifier = NotificationRequestIdentifier(
            occurrenceID: occurrence.id,
            kind: .snooze
        ).rawValue
        #expect(fixture.scheduler.pending[snoozeIdentifier] != nil)

        // 已送达卡片与挂起队列独立；完成时必须同时清理两份系统集合。
        let primaryIdentifier = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        fixture.scheduler.delivered = [primaryIdentifier, snoozeIdentifier]

        _ = try TaskProgressService(context: fixture.context).complete(
            occurrence,
            at: fixture.now,
            source: .childManual
        )
        let result = try await fixture.service.rebuild(at: fixture.now)

        #expect(result.reconciliation.removedIdentifiers.contains(snoozeIdentifier))
        #expect(fixture.scheduler.pending[snoozeIdentifier] == nil)
        #expect(fixture.scheduler.delivered.isEmpty)
        #expect(
            try NotificationLinkStore(context: fixture.context)
                .links(occurrenceID: occurrence.id)
                .isEmpty
        )
    }

    @Test("读取系统队列失败时保留清理映射，下一次重建仍可追溯")
    func failedPendingReadPreservesSnoozeLink() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first {
                $0.dateKey == "2026-09-27"
            }
        )
        _ = try await TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler,
            permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone
        ).schedule(occurrenceID: occurrence.id, at: fixture.now)
        _ = try TaskProgressService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual
        )
        fixture.scheduler.readFails = true

        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(!result.reconciliation.isSuccessful)
        #expect(
            try NotificationLinkStore(context: fixture.context)
                .links(occurrenceID: occurrence.id).contains { $0.kind == .snooze }
        )
        fixture.scheduler.readFails = false
        _ = try await fixture.service.rebuild(at: fixture.now)
        #expect(try NotificationLinkStore(context: fixture.context).links(occurrenceID: occurrence.id).isEmpty)
    }

    @Test("已送达集合读取失败时保留完成任务映射，重试后才清理")
    func failedDeliveredReadPreservesTraceableLinks() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        let identifier = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .primary).rawValue
        fixture.scheduler.delivered = [identifier]
        _ = try TaskProgressService(context: fixture.context).complete(
            occurrence, at: fixture.now, source: .childManual)
        fixture.scheduler.deliveredReadFails = true
        let failed = try await fixture.service.rebuild(at: fixture.now)
        #expect(failed.reconciliation.failures.contains { $0.operation == .readDelivered })
        #expect(fixture.scheduler.pending[identifier] == nil)
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: identifier) != nil)

        fixture.scheduler.deliveredReadFails = false
        fixture.scheduler.deliveredRemovalFails = true
        let retryFailed = try await fixture.service.rebuild(at: fixture.now)
        #expect(retryFailed.reconciliation.failures.contains { $0.operation == .removeDelivered })
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: identifier) != nil)
        fixture.scheduler.deliveredRemovalFails = false
        let restored = try await fixture.service.rebuild(at: fixture.now)
        #expect(restored.reconciliation.isSuccessful)
        #expect(fixture.scheduler.delivered.isEmpty)
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: identifier) == nil)
    }

    @Test("前台重建等待系统队列时创建稍后提醒不会丢失")
    func rebuildAndSnoozeShareOneTransactionBoundary() async throws {
        let fixture = try Fixture()
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" }
        )
        let snooze = TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler,
            permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone,
            operationGate: fixture.operationGate
        )
        let entered = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let snoozeStarted = AsyncStream.makeStream(of: Void.self)
        fixture.scheduler.onReadAsync = {
            entered.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        let rebuilding = Task { try await fixture.service.rebuild(at: fixture.now) }
        var enteredIterator = entered.stream.makeAsyncIterator()
        _ = await enteredIterator.next()
        let snoozing = Task {
            snoozeStarted.continuation.yield(())
            return try await snooze.schedule(occurrenceID: occurrence.id, at: fixture.now)
        }
        var snoozeIterator = snoozeStarted.stream.makeAsyncIterator()
        _ = await snoozeIterator.next()
        release.continuation.yield(())
        _ = try await rebuilding.value
        let scheduledAt = try await snoozing.value

        let identifier = NotificationRequestIdentifier(occurrenceID: occurrence.id, kind: .snooze).rawValue
        #expect(fixture.scheduler.pending[identifier]?.scheduledAt == scheduledAt)
        #expect(try NotificationLinkStore(context: fixture.context).link(requestIdentifier: identifier) != nil)
        let result = try await fixture.service.rebuild(at: fixture.now)
        #expect(result.reconciliation.retainedIdentifiers.contains(identifier))
    }
}

@MainActor
private extension NotificationRebuildServiceTests {
    func seedApprovalNotifications(at url: URL, outcome: Int) async throws -> (UUID, UUID) {
        let (fixture, occurrence) = try await approvalSetup(storeURL: url)
        _ = try await snoozeService(fixture).schedule(occurrenceID: occurrence.id, at: fixture.now)
        let row = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
        if outcome != 0 {
            _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
                occurrence, submissionID: row.submissionID, at: fixture.now)
            if outcome == 2 {
                _ = try await snoozeService(fixture).schedule(occurrenceID: occurrence.id, at: fixture.now)
            }
        }
        return (occurrence.id, row.submissionID)
    }

    /// 显式合成模板经正式物化传播配置；11/7/3 不是产品默认，也不绕过普通实例核对。
    func approvalSetup(zero: Bool = false, storeURL: URL? = nil) async throws -> (Fixture, TaskOccurrence) {
        let fixture = try Fixture(storeURL: storeURL)
        let template = try fixture.insertDailyTemplate()
        template.verificationTypeRawValue = TaskVerificationType.parentApproval.rawValue
        template.xpReward = zero ? 0 : 11
        template.coinReward = zero ? 0 : 7
        template.activeBonusCoin = zero ? 0 : 3
        try fixture.context.save()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" })
        #expect(occurrence.verificationTypeSnapshot == .parentApproval)
        #expect(occurrence.xpRewardSnapshot == (zero ? 0 : 11))
        #expect(occurrence.coinRewardSnapshot == (zero ? 0 : 7) && occurrence.activeBonusCoinSnapshot == (zero ? 0 : 3))
        #expect(!fixture.context.hasChanges)
        return (fixture, occurrence)
    }

    func snoozeService(_ fixture: Fixture) -> TaskSnoozeService {
        TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler, permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone, operationGate: fixture.operationGate)
    }

    func seedNotifications(storeURL: URL) async throws -> (UUID, Date) {
        let fixture = try Fixture(storeURL: storeURL)
        _ = try fixture.insertDailyTemplate()
        _ = try await fixture.service.rebuild(at: fixture.now)
        let occurrence = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == "2026-09-27" })
        let scheduledAt = try await TaskSnoozeService(
            context: fixture.context, scheduler: fixture.scheduler, permissionProvider: fixture.permissions,
            calendar: fixture.calendar, timeZone: fixture.timeZone
        ).schedule(occurrenceID: occurrence.id, at: fixture.now)
        return (occurrence.id, scheduledAt)
    }

    final class Fixture {
        let context: ModelContext
        let scheduler: RebuildSchedulerFake
        let service: NotificationRebuildService
        let now: Date
        let calendar: Calendar
        let timeZone: TimeZone
        let operationGate = NotificationOperationGate()
        let permissions = FakeLocalNotificationService()

        init(storeURL: URL? = nil) throws {
            if let storeURL {
                context = ModelContext(try AppModelContainer.make(storeURL: storeURL))
            } else {
                context = ModelContext(try AppModelContainer.make(inMemory: true))
            }
            scheduler = RebuildSchedulerFake()
            permissions.currentAuthorizationState = .authorized
            now = try Date("2026-09-27T02:00:00Z", strategy: .iso8601)
            calendar = Calendar(identifier: .gregorian)
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            service = NotificationRebuildService(
                context: context,
                scheduler: scheduler,
                permissionProvider: permissions,
                calendar: calendar,
                timeZone: timeZone,
                operationGate: operationGate
            )
        }

        func insertDailyTemplate() throws -> TaskTemplate {
            let start = try LocalDate(dateKey: "2026-09-27")
            let template = TaskTemplate(
                title: "阅读",
                iconName: "book.fill",
                colorToken: "reading",
                targetDurationSeconds: 900,
                createdAt: now,
                updatedAt: now
            )
            let rule = ReminderRule(
                taskTemplateID: template.id,
                recurrence: try .weekly(on: Set(Weekday.allCases), starting: start),
                timeOfDayMinutes: 19 * 60 + 30
            )
            context.insert(template)
            context.insert(rule)
            // 兼容 iPadOS 17：先建立持久化归属，避免尚未入库模型的双向关系触发陷阱。
            template.reminderRule = rule
            rule.taskTemplate = template
            try context.save()
            return template
        }
    }

    final class RebuildSchedulerFake: NotificationRequestScheduling {
        var pending: [String: PendingNotificationRequestSnapshot] = [:]
        var addCount = 0
        var readFails = false
        var addFails = false
        var deliveredReadFails = false
        var deliveredRemovalFails = false
        var pendingRemovalFails = false
        var delivered: Set<String> = []
        var onReadAsync: (() async throws -> Void)?
        var onAdd: ((TaskNotificationRequest) throws -> Void)?

        func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
            if readFails { throw CocoaError(.fileReadUnknown) }
            if let onReadAsync {
                self.onReadAsync = nil
                try await onReadAsync()
            }
            return Array(pending.values)
        }

        func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
            if addFails { throw CocoaError(.fileWriteUnknown) }
            if let onAdd {
                self.onAdd = nil
                try onAdd(request)
            }
            addCount += 1
            pending[request.identifier] = PendingNotificationRequestSnapshot(
                identifier: request.identifier,
                title: request.title,
                body: request.body,
                scheduledAt: request.scheduledAt
            )
        }

        func removePendingNotificationRequest(identifier: String) async throws {
            if pendingRemovalFails { throw CocoaError(.fileWriteUnknown) }
            pending[identifier] = nil
        }

        func deliveredNotificationIdentifiers() async throws -> [String] {
            if deliveredReadFails { throw CocoaError(.fileReadUnknown) }
            return Array(delivered)
        }

        func removeDeliveredNotificationRequest(identifier: String) async throws {
            if deliveredRemovalFails { throw CocoaError(.fileWriteUnknown) }
            delivered.remove(identifier)
        }
    }
}
