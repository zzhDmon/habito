import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("任务实例幂等核对")
struct TaskOccurrenceReconciliationServiceTests {
    @Test("相同候选连续核对五次不重复且稳定身份")
    func fiveReconciliationsRemainIdempotent() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        try context.save()
        let today = try localDate("2026-09-23")
        let end = try localDate("2026-09-30")
        let candidates = [
            try candidate("2026-09-23", hour: 19, revision: 1),
            try candidate("2026-09-24", hour: 19, revision: 1),
        ]
        let service = TaskOccurrenceReconciliationService(context: context)
        let now = try instant("2026-09-23T01:00:00Z")

        var originalIDs: Set<UUID> = []
        for iteration in 0..<5 {
            let report = try service.reconcile(
                template: template,
                candidates: candidates,
                in: today...end,
                today: today,
                now: now
            )
            let occurrences = try fetchOccurrences(context)

            #expect(occurrences.count == 2)
            #expect(Set(occurrences.map(\.uniquenessKey)).count == 2)
            if iteration == 0 {
                #expect(report.insertedCount == 2)
                originalIDs = Set(occurrences.map(\.id))
            } else {
                #expect(report == .init(insertedCount: 0, updatedCount: 0, deletedCount: 0, protectedCount: 0))
                #expect(Set(occurrences.map(\.id)) == originalIDs)
            }
        }
    }

    @Test("模板修订只原位更新今天和未来的普通待处理实例")
    func templateRevisionUpdatesOnlyMutableOccurrences() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let today = try localDate("2026-09-23")
        let mutable = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let inProgress = try occurrence(template: template, dateKey: "2026-09-25", status: .inProgress)
        let completed = try occurrence(template: template, dateKey: "2026-09-26", status: .completed)
        let skipped = try occurrence(template: template, dateKey: "2026-09-27", status: .skipped)
        let detached = try occurrence(
            template: template,
            dateKey: "2026-09-28",
            status: .pending,
            detached: true
        )
        let past = try occurrence(template: template, dateKey: "2026-09-22", status: .pending)
        [mutable, inProgress, completed, skipped, detached, past].forEach(context.insert)
        try context.save()
        let mutableID = mutable.id

        template.title = "新版阅读"
        template.targetDurationSeconds = 1_200
        template.revision = 2
        let candidates = try ["24", "25", "26", "27", "28"].map {
            try candidate("2026-09-\($0)", hour: 20, revision: 2)
        }
        let report = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: candidates,
            in: localDate("2026-09-22")...localDate("2026-09-30"),
            today: today,
            now: instant("2026-09-23T02:00:00Z")
        )

        #expect(report.updatedCount == 1)
        #expect(report.protectedCount == 5)
        #expect(mutable.id == mutableID)
        #expect(mutable.titleSnapshot == "新版阅读")
        #expect(mutable.targetDurationSnapshot == 1_200)
        #expect(mutable.sourceRevision == 2)
        #expect(inProgress.titleSnapshot == "阅读")
        #expect(completed.titleSnapshot == "阅读")
        #expect(skipped.titleSnapshot == "阅读")
        #expect(detached.titleSnapshot == "阅读")
        #expect(past.titleSnapshot == "阅读")
    }

    @Test("模板归档只移除范围内未来普通待处理实例")
    func archivedTemplateRemovesOnlyMutableFutureOccurrences() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let removable = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let completed = try occurrence(template: template, dateKey: "2026-09-25", status: .completed)
        let detached = try occurrence(
            template: template,
            dateKey: "2026-09-26",
            status: .pending,
            detached: true
        )
        let outsideRange = try occurrence(template: template, dateKey: "2026-10-02", status: .pending)
        [removable, completed, detached, outsideRange].forEach(context.insert)
        try context.save()
        template.archivedAt = try instant("2026-09-23T03:00:00Z")

        let report = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: [],
            in: localDate("2026-09-23")...localDate("2026-09-30"),
            today: localDate("2026-09-23"),
            now: instant("2026-09-23T03:00:00Z")
        )
        let remaining = try fetchOccurrences(context)

        #expect(report.deletedCount == 1)
        #expect(report.protectedCount == 2)
        #expect(Set(remaining.map(\.id)) == [completed.id, detached.id, outsideRange.id])
    }

    @Test("范围外候选和过期修订会在写入前拒绝")
    func invalidCandidatesAreRejectedBeforeWrite() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        try context.save()
        let today = try localDate("2026-09-23")
        let service = TaskOccurrenceReconciliationService(context: context)

        #expect(throws: OccurrenceReconciliationError.candidateRevisionMismatch(candidate: 2, template: 1)) {
            try service.reconcile(
                template: template,
                candidates: [candidate("2026-09-24", hour: 19, revision: 2)],
                in: today...localDate("2026-09-30"),
                today: today,
                now: instant("2026-09-23T01:00:00Z")
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
    }

    @Test("损坏的存量状态在任何实例被修改前失败")
    func invalidStoredStateDoesNotPartiallyUpdateContext() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let valid = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let invalid = try occurrence(template: template, dateKey: "2026-09-25", status: .pending)
        invalid.statusRawValue = "unknown"
        context.insert(valid)
        context.insert(invalid)
        try context.save()
        let originalTime = valid.scheduledAt

        #expect(
            throws: OccurrenceReconciliationError.invalidStoredStatus(
                occurrenceID: invalid.id,
                rawValue: "unknown"
            )
        ) {
            try TaskOccurrenceReconciliationService(context: context).reconcile(
                template: template,
                candidates: [
                    candidate("2026-09-24", hour: 20, revision: 1),
                    candidate("2026-09-25", hour: 20, revision: 1),
                ],
                in: localDate("2026-09-23")...localDate("2026-09-30"),
                today: localDate("2026-09-23"),
                now: instant("2026-09-23T04:00:00Z")
            )
        }

        #expect(valid.scheduledAt == originalTime)
        #expect(valid.titleSnapshot == "阅读")
    }

    private func makeContext() throws -> ModelContext {
        try ModelContext(AppModelContainer.make(inMemory: true))
    }

    private func makeTemplate() -> TaskTemplate {
        TaskTemplate(
            title: "阅读",
            iconName: "book.fill",
            colorToken: "reading",
            targetDurationSeconds: 900
        )
    }

    private func occurrence(
        template: TaskTemplate,
        dateKey: String,
        status: TaskOccurrenceStatus,
        detached: Bool = false
    ) throws -> TaskOccurrence {
        let date = try localDate(dateKey)
        let occurrence = TaskOccurrence(
            templateID: template.id,
            date: date,
            scheduledAt: try scheduledAt(dateKey, hour: 19),
            titleSnapshot: template.title,
            iconSnapshot: template.iconName,
            colorSnapshot: template.colorToken,
            targetDurationSnapshot: template.targetDurationSeconds,
            status: status,
            sourceRevision: template.revision,
            isDetachedOverride: detached
        )
        occurrence.template = template
        return occurrence
    }

    private func candidate(
        _ dateKey: String,
        hour: Int,
        revision: Int
    ) throws -> ResolvedTaskCandidate {
        .init(
            date: try localDate(dateKey),
            scheduledAt: try scheduledAt(dateKey, hour: hour),
            origin: .generated(templateRevision: revision)
        )
    }

    private func scheduledAt(_ dateKey: String, hour: Int) throws -> Date {
        let date = try localDate(dateKey)
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        return try #require(
            TaskRecurrenceExpander(calendar: .init(identifier: .gregorian), timeZone: timeZone)
                .expand(
                    .once(on: date),
                    timeOfDayMinutes: hour * 60,
                    from: date,
                    through: date
                ).first?.scheduledAt
        )
    }

    private func fetchOccurrences(_ context: ModelContext) throws -> [TaskOccurrence] {
        try context.fetch(FetchDescriptor<TaskOccurrence>())
    }

    private func localDate(_ dateKey: String) throws -> LocalDate {
        try LocalDate(dateKey: dateKey)
    }

    private func instant(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }
}
