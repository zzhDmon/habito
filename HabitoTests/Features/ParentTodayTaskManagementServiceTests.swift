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

    private final class Fixture {
        let context: ModelContext
        let template: TaskTemplate
        let occurrence: TaskOccurrence
        let service: ParentTodayTaskManagementService
        let now: Date

        init(status: TaskOccurrenceStatus = .pending) throws {
            context = ModelContext(try AppModelContainer.make(inMemory: true))
            now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
            let date = try LocalDate(dateKey: "2026-09-23")
            let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
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
            template.reminderRule = rule
            rule.taskTemplate = template
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
            occurrence.template = template
            context.insert(template)
            context.insert(rule)
            context.insert(occurrence)
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
