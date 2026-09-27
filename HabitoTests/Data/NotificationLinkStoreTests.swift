import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("通知标识与映射存储")
@MainActor
struct NotificationLinkStoreTests {
    @Test("主提醒与稍后提醒标识稳定且可反查")
    func identifiersAreStableAndReversible() throws {
        let id = try #require(UUID(uuidString: "C5412144-2FB8-4E96-9F7A-6A42E0803D11"))
        let primary = NotificationRequestIdentifier(occurrenceID: id, kind: .primary)
        let snooze = NotificationRequestIdentifier(occurrenceID: id, kind: .snooze)

        #expect(primary.rawValue == "habito.occurrence.c5412144-2fb8-4e96-9f7a-6a42e0803d11.primary")
        #expect(primary.rawValue != snooze.rawValue)
        #expect(NotificationRequestIdentifier(rawValue: primary.rawValue) == primary)
        #expect(NotificationRequestIdentifier(rawValue: snooze.rawValue) == snooze)
        #expect(NotificationRequestIdentifier(rawValue: "other.occurrence.\(id).primary") == nil)
    }

    @Test("同一实例两类通知共存且重复写入只更新时间")
    func upsertIsIdempotentAndKindsCoexist() throws {
        let fixture = try makeFixture()
        let firstTime = Date(timeIntervalSince1970: 1_800_000_000)
        let replacementTime = firstTime.addingTimeInterval(600)

        let first = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id,
            kind: .primary,
            scheduledAt: firstTime
        )
        let replacement = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id,
            kind: .primary,
            scheduledAt: replacementTime
        )
        _ = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id,
            kind: .snooze,
            scheduledAt: replacementTime
        )

        #expect(first.requestIdentifier == replacement.requestIdentifier)
        #expect(replacement.scheduledAt == replacementTime)
        #expect(try fixture.store.links(occurrenceID: fixture.occurrence.id).count == 2)
    }

    @Test("旧格式同用途映射由稳定标识替换")
    func replacesLegacyMapping() throws {
        let fixture = try makeFixture()
        let legacy = NotificationLink(
            requestIdentifier: "occurrence.legacy.primary",
            occurrenceID: fixture.occurrence.id,
            kind: .primary,
            scheduledAt: fixture.occurrence.scheduledAt
        )
        legacy.occurrence = fixture.occurrence
        fixture.context.insert(legacy)
        try fixture.context.save()

        let link = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id,
            kind: .primary,
            scheduledAt: fixture.occurrence.scheduledAt
        )

        #expect(link.requestIdentifier.hasPrefix("habito.occurrence."))
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 1)
    }

    @Test("系统标识可反查实例且单类删除不影响另一类")
    func lookupAndRemoveOneKind() throws {
        let fixture = try makeFixture()
        let primary = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id,
            kind: .primary,
            scheduledAt: fixture.occurrence.scheduledAt
        )
        _ = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id,
            kind: .snooze,
            scheduledAt: fixture.occurrence.scheduledAt
        )

        let resolved = try fixture.store.link(requestIdentifier: primary.requestIdentifier)
        #expect(resolved?.occurrenceID == fixture.occurrence.id)

        try fixture.store.remove(occurrenceID: fixture.occurrence.id, kind: .primary)
        let remaining = try fixture.store.links(occurrenceID: fixture.occurrence.id)
        #expect(remaining.map(\.kind) == [.snooze])
    }

    @Test("不存在实例时拒绝创建孤立映射")
    func rejectsMissingOccurrence() throws {
        let fixture = try makeFixture()
        let missingID = UUID()

        #expect(throws: NotificationLinkStoreError.occurrenceNotFound(missingID)) {
            try fixture.store.upsert(
                occurrenceID: missingID,
                kind: .primary,
                scheduledAt: fixture.occurrence.scheduledAt
            )
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("损坏用途与实例不一致均显式拒绝")
    func rejectsCorruptedMappings() throws {
        let fixture = try makeFixture()
        let link = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id,
            kind: .primary,
            scheduledAt: fixture.occurrence.scheduledAt
        )
        link.kindRawValue = "broken"
        try fixture.context.save()

        #expect(throws: NotificationLinkStoreError.self) {
            try fixture.store.link(requestIdentifier: link.requestIdentifier)
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        let date = try LocalDate(dateKey: "2026-09-25")
        let occurrence = TaskOccurrence(
            templateID: UUID(),
            date: date,
            scheduledAt: Date(timeIntervalSince1970: 1_800_000_000),
            titleSnapshot: "阅读",
            iconSnapshot: "book.fill",
            colorSnapshot: "task",
            targetDurationSnapshot: 900,
            sourceRevision: 1
        )
        context.insert(occurrence)
        try context.save()
        return Fixture(
            container: container,
            context: context,
            occurrence: occurrence,
            store: NotificationLinkStore(context: context)
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let occurrence: TaskOccurrence
        let store: NotificationLinkStore
    }
}
