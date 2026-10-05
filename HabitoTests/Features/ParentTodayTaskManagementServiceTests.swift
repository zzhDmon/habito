import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("家长今日实例管理事务")
@MainActor
struct ParentTodayTaskManagementServiceTests {
    @Test("同日调时只修改当前实例并脱离模板")
    func rescheduleDetachesOnlyOccurrence() throws {
        let fixture = try Fixture()
        let originalTemplateRevision = fixture.template.revision
        let newTime = try fixture.instant("2026-09-23T12:15:00Z")

        try fixture.service.reschedule(
            occurrenceID: fixture.occurrence.id,
            to: newTime,
            at: fixture.now
        )

        #expect(fixture.occurrence.scheduledAt == newTime)
        #expect(fixture.occurrence.isDetachedOverride)
        #expect(fixture.template.revision == originalTemplateRevision)
        #expect(fixture.template.reminderRule?.timeOfDayMinutes == 19 * 60 + 30)
    }

    @Test("家长单日修改成功后请求重建通知")
    func viewModelRequestsNotificationRebuildAfterReschedule() throws {
        let fixture = try Fixture()
        let trigger = NotificationRebuildTrigger()
        let model = ParentTodayTaskViewModel(
            context: fixture.context,
            calendar: Calendar(identifier: .gregorian),
            timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now),
            notificationRebuildTrigger: trigger
        )

        model.reschedule(
            occurrenceID: fixture.occurrence.id,
            to: try fixture.instant("2026-09-23T12:15:00Z")
        )

        #expect(trigger.revision == 1)
        #expect(fixture.occurrence.isDetachedOverride)
    }

    @Test("跨日调时被拒绝且实例保持原值")
    func rescheduleRejectsDifferentLocalDate() throws {
        let fixture = try Fixture()
        let originalTime = fixture.occurrence.scheduledAt

        #expect(
            throws: ParentTodayTaskManagementError.scheduledTimeOutsideOccurrenceDate(
                occurrenceID: fixture.occurrence.id
            )
        ) {
            try fixture.service.reschedule(
                occurrenceID: fixture.occurrence.id,
                to: fixture.instant("2026-09-23T16:15:00Z"),
                at: fixture.now
            )
        }
        #expect(fixture.occurrence.scheduledAt == originalTime)
        #expect(!fixture.occurrence.isDetachedOverride)
    }

    @Test("待处理实例可以跳过并恢复")
    func skipAndRestoreFollowStateMachine() throws {
        let fixture = try Fixture()

        try fixture.service.skip(occurrenceID: fixture.occurrence.id, at: fixture.now)
        #expect(fixture.occurrence.status == .skipped)

        try fixture.service.restore(occurrenceID: fixture.occurrence.id, at: fixture.now)
        #expect(fixture.occurrence.status == .pending)
    }

    @Test(
        "家长更正完成写入明确来源且不伪造时长",
        arguments: [
            TaskOccurrenceStatus.pending, .skipped,
        ])
    func parentCorrectionWritesSource(status: TaskOccurrenceStatus) throws {
        let fixture = try Fixture(status: status)

        try fixture.service.correctAsCompleted(
            occurrenceID: fixture.occurrence.id,
            at: fixture.now
        )

        #expect(fixture.occurrence.status == .completed)
        #expect(fixture.occurrence.completionRecord?.completionSource == .parentCorrection)
        #expect(fixture.occurrence.completionRecord?.activeDurationSeconds == 0)
    }

    @Test("进行中实例拒绝家长强制完成")
    func inProgressCannotBeCorrected() throws {
        let fixture = try Fixture(status: .inProgress)
        let session = TimerSession(
            occurrenceID: fixture.occurrence.id,
            state: .paused,
            startedAt: try fixture.instant("2026-09-23T03:00:00Z"),
            lastResumedAt: try fixture.instant("2026-09-23T03:00:00Z"),
            accumulatedActiveSeconds: 300
        )
        session.occurrence = fixture.occurrence
        fixture.context.insert(session)
        try fixture.context.save()

        #expect(
            throws: ParentTodayTaskManagementError.inProgressCannotBeCorrected(
                occurrenceID: fixture.occurrence.id
            )
        ) {
            try fixture.service.correctAsCompleted(
                occurrenceID: fixture.occurrence.id,
                at: fixture.now
            )
        }
        #expect(fixture.occurrence.status == .inProgress)
        #expect(fixture.occurrence.completionRecord == nil)
    }

    @Test("家长跳过更正显式奖励原子入账，来源和自主边界仍明确")
    func skippedCorrectionSettlesExplicitRewards() throws {
        let fixture = try Fixture(status: .skipped)
        fixture.occurrence.xpRewardSnapshot = 11
        fixture.occurrence.coinRewardSnapshot = 7
        fixture.occurrence.activeBonusCoinSnapshot = 3
        try fixture.context.save()
        try fixture.service.correctAsCompleted(occurrenceID: fixture.occurrence.id, at: fixture.now)
        let record = try #require(fixture.occurrence.completionRecord)
        #expect(record.completionSource == .parentCorrection && record.completionTiming == .beforeReminder)
        #expect(record.rewardSettlementVersion == 1 && record.settledCoinSnapshot == 10)
        #expect(
            try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 11, coins: 10))
    }

    @Test("家长跳过更正保存失败恢复 skipped，不留下中间恢复和奖励")
    func failedSkippedCorrectionRestoresSkipped() throws {
        let fixture = try Fixture(status: .skipped)
        let originalUpdatedAt = fixture.occurrence.updatedAt
        let service = ParentTodayTaskManagementService(
            context: fixture.context, calendar: Calendar(identifier: .gregorian), timeZone: fixture.timeZone,
            completionService: TaskCompletionService(
                context: fixture.context,
                saveChanges: { _ in
                    throw NSError(domain: "HabitoSyntheticSave", code: 1)
                }))
        #expect(throws: NSError.self) {
            try service.correctAsCompleted(occurrenceID: fixture.occurrence.id, at: fixture.now)
        }
        #expect(fixture.occurrence.status == .skipped && fixture.occurrence.updatedAt == originalUpdatedAt)
        #expect(fixture.occurrence.completionRecord == nil && !fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
        #expect(try RewardLedgerService(context: fixture.context).balance() == RewardBalance(effectiveXP: 0, coins: 0))
    }

    @Test("家长更正失败不触发通知重建且可见操作错误")
    func failedParentCorrectionDoesNotRequestRebuild() throws {
        let fixture = try Fixture(status: .skipped)
        let trigger = NotificationRebuildTrigger()
        let model = ParentTodayTaskViewModel(
            context: fixture.context, calendar: Calendar(identifier: .gregorian), timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now), notificationRebuildTrigger: trigger,
            completionService: TaskCompletionService(
                context: fixture.context,
                saveChanges: { _ in
                    throw NSError(domain: "HabitoSyntheticSave", code: 1)
                }))
        model.load()
        model.correctAsCompleted(occurrenceID: fixture.occurrence.id)
        #expect(model.isActionErrorPresented && trigger.revision == 0)
        #expect(fixture.occurrence.status == .skipped && !fixture.context.hasChanges)
    }

    @Test("家长更正不能绕过验收配置，拒绝后仍为原 skipped")
    func skippedCorrectionCannotBypassApproval() throws {
        let fixture = try Fixture(status: .skipped)
        fixture.occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        try fixture.context.save()
        #expect(throws: TaskCompletionServiceError.requiresParentApproval(fixture.occurrence.id)) {
            try fixture.service.correctAsCompleted(occurrenceID: fixture.occurrence.id, at: fixture.now)
        }
        #expect(fixture.occurrence.status == .skipped && !fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
    }

    private final class Fixture {
        let context: ModelContext
        let template: TaskTemplate
        let occurrence: TaskOccurrence
        let service: ParentTodayTaskManagementService
        let now: Date
        let timeZone: TimeZone

        init(status: TaskOccurrenceStatus = .pending) throws {
            context = ModelContext(try AppModelContainer.make(inMemory: true))
            now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
            let date = try LocalDate(dateKey: "2026-09-23")
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
            template = TaskTemplate(
                title: "阅读",
                iconName: "book.fill",
                colorToken: "reading",
                targetDurationSeconds: 900
            )
            let rule = ReminderRule(
                taskTemplateID: template.id,
                recurrence: try .weekly(on: Set(Weekday.allCases), starting: date),
                timeOfDayMinutes: 19 * 60 + 30
            )
            occurrence = TaskOccurrence(
                templateID: template.id,
                date: date,
                scheduledAt: try Date("2026-09-23T11:30:00Z", strategy: .iso8601),
                titleSnapshot: template.title,
                iconSnapshot: template.iconName,
                colorSnapshot: template.colorToken,
                targetDurationSnapshot: template.targetDurationSeconds,
                status: status,
                sourceRevision: template.revision
            )
            context.insert(template)
            context.insert(rule)
            context.insert(occurrence)
            template.reminderRule = rule
            rule.taskTemplate = template
            occurrence.template = template
            try context.save()
            service = ParentTodayTaskManagementService(
                context: context,
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
        }

        func instant(_ value: String) throws -> Date {
            try Date(value, strategy: .iso8601)
        }
    }
}
