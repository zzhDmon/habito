import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("SwiftData 持久化往返")
struct PersistenceRoundTripTests {
    @Test("八个模型增删改后重新打开保持一致")
    func persistsCrudAndRelationshipsAcrossReopen() throws {
        let directoryURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let storeURL = directoryURL.appending(path: "Habito.store")
        let fixture = try makeFixture()
        try seedStore(at: storeURL, fixture: fixture)
        try updateAndDeleteAfterReopen(at: storeURL)
        try verifyAfterSecondReopen(at: storeURL, fixture: fixture)
    }

    private func seedStore(at storeURL: URL, fixture: PersistenceFixture) throws {
        let container = try AppModelContainer.make(storeURL: storeURL)
        let context = ModelContext(container)

        fixture.template.reminderRule = fixture.rule
        fixture.occurrence.template = fixture.template
        fixture.occurrence.completionRecord = fixture.completion
        fixture.session.occurrence = fixture.occurrence
        fixture.link.occurrence = fixture.occurrence

        context.insert(fixture.template)
        context.insert(fixture.occurrence)
        context.insert(fixture.session)
        context.insert(fixture.link)
        context.insert(fixture.dayOverride)
        context.insert(fixture.settings)
        try context.save()
    }

    private func updateAndDeleteAfterReopen(at storeURL: URL) throws {
        let container = try AppModelContainer.make(storeURL: storeURL)
        let context = ModelContext(container)
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let links = try context.fetch(FetchDescriptor<NotificationLink>())

        let template = try #require(templates.first)
        template.title = "每天阅读"
        template.updatedAt = .now
        context.delete(try #require(links.first))
        try context.save()
    }

    private func verifyAfterSecondReopen(at storeURL: URL, fixture: PersistenceFixture) throws {
        let container = try AppModelContainer.make(storeURL: storeURL)
        let context = ModelContext(container)
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let occurrences = try context.fetch(FetchDescriptor<TaskOccurrence>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>())

        let template = try #require(templates.first)
        let occurrence = try #require(occurrences.first)
        let appSettings = try #require(settings.first)

        #expect(templates.count == 1)
        #expect(template.id == fixture.templateID)
        #expect(template.title == "每天阅读")
        #expect(template.reminderRule?.scheduleType == .weekly)
        #expect(template.reminderRule?.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(occurrence.template?.id == fixture.templateID)
        #expect(occurrence.completionRecord?.completionSource == .childManual)
        #expect(occurrence.timerSessions.count == 1)
        #expect(occurrence.notificationLinks.isEmpty)
        #expect(appSettings.hasParentPIN)
        #expect(appSettings.parentPINCredentialKey == AppSettings.parentPINKeychainAccount)
        #expect(try context.fetchCount(FetchDescriptor<DayOverride>()) == 1)
    }

    private func makeFixture() throws -> PersistenceFixture {
        let templateID = UUID()
        let occurrenceID = UUID()
        let date = try LocalDate(dateKey: "2026-09-23")
        let startDate = try LocalDate(dateKey: "2026-09-01")
        let recurrence = try TaskRecurrence.weekly(on: Weekday.schoolDays, starting: startDate)
        let scheduledAt = try Date("2026-09-23T11:30:00Z", strategy: .iso8601)
        let completedAt = try Date("2026-09-23T11:47:00Z", strategy: .iso8601)

        let template = TaskTemplate(
            id: templateID,
            title: "阅读",
            iconName: "book.fill",
            colorToken: "reading",
            targetDurationSeconds: 900
        )
        let rule = ReminderRule(
            taskTemplateID: templateID,
            recurrence: recurrence,
            timeOfDayMinutes: 19 * 60 + 30
        )
        let occurrence = TaskOccurrence(
            id: occurrenceID,
            templateID: templateID,
            date: date,
            scheduledAt: scheduledAt,
            titleSnapshot: "阅读",
            iconSnapshot: "book.fill",
            colorSnapshot: "reading",
            targetDurationSnapshot: 900,
            status: .completed,
            sourceRevision: 1
        )
        let completion = CompletionRecord(
            occurrenceID: occurrenceID,
            completedAt: completedAt,
            activeDurationSeconds: 900,
            completionSource: .childManual
        )
        let session = TimerSession(
            occurrenceID: occurrenceID,
            state: .ended,
            startedAt: scheduledAt,
            lastResumedAt: scheduledAt,
            accumulatedActiveSeconds: 900,
            endedAt: completedAt
        )
        let link = NotificationLink(
            requestIdentifier: "occurrence.\(occurrenceID.uuidString).primary",
            occurrenceID: occurrenceID,
            kind: .primary,
            scheduledAt: scheduledAt
        )
        let dayOverride = DayOverride(date: date, dayType: .schoolDay, note: "调休上课")
        let settings = AppSettings(
            isOnboardingCompleted: true,
            hasParentPIN: true,
            schedulingHorizonDateKey: "2026-10-01",
            lastNotificationAuthorization: .authorized
        )

        return PersistenceFixture(
            templateID: templateID,
            template: template,
            rule: rule,
            occurrence: occurrence,
            completion: completion,
            session: session,
            link: link,
            dayOverride: dayOverride,
            settings: settings
        )
    }
}
