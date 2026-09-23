import Foundation
import SwiftData
import Testing
@testable import Habito

/// 今日查询测试使用的固定时区、日期和内存存储夹具。
@MainActor
struct TodayQueryFixture {
    let context: ModelContext
    let date: LocalDate
    let now: Date
    let calendar: Calendar
    let timeZone: TimeZone

    init() throws {
        context = try ModelContext(AppModelContainer.make(inMemory: true))
        date = try LocalDate(dateKey: "2026-09-23")
        now = try Date("2026-09-23T04:00:00Z", strategy: .iso8601)
        calendar = Calendar(identifier: .gregorian)
        timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    }

    func makeOccurrence(
        title: String,
        scheduledAt: Date,
        status: TaskOccurrenceStatus,
        date occurrenceDate: LocalDate? = nil
    ) -> TaskOccurrence {
        let occurrence = TaskOccurrence(
            templateID: UUID(),
            date: occurrenceDate ?? date,
            scheduledAt: scheduledAt,
            titleSnapshot: title,
            iconSnapshot: "book.fill",
            colorSnapshot: "reading",
            targetDurationSnapshot: 900,
            status: status,
            sourceRevision: 1,
            createdAt: now,
            updatedAt: now
        )
        context.insert(occurrence)
        return occurrence
    }

    func addSession(
        to occurrence: TaskOccurrence,
        state: TimerSessionState,
        startedAt: Date,
        lastResumedAt: Date,
        accumulatedSeconds: TimeInterval,
        endedAt: Date? = nil
    ) {
        let session = TimerSession(
            occurrenceID: occurrence.id,
            state: state,
            startedAt: startedAt,
            lastResumedAt: lastResumedAt,
            accumulatedActiveSeconds: accumulatedSeconds,
            endedAt: endedAt
        )
        session.occurrence = occurrence
        context.insert(session)
    }

    func addCompletion(
        to occurrence: TaskOccurrence,
        at completedAt: Date,
        activeSeconds: TimeInterval = 0
    ) {
        let record = CompletionRecord(
            occurrenceID: occurrence.id,
            completedAt: completedAt,
            activeDurationSeconds: activeSeconds,
            completionSource: .childManual,
            createdAt: completedAt,
            updatedAt: completedAt
        )
        occurrence.completionRecord = record
        context.insert(record)
    }

    func snapshot() throws -> TodayTasksSnapshot {
        try context.save()
        return try TodayTaskQueryService(
            context: context,
            calendar: calendar,
            timeZone: timeZone
        ).snapshot(for: date, at: now)
    }
}
