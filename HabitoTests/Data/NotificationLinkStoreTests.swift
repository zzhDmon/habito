import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("通知标识与映射存储")
@MainActor
struct NotificationLinkStoreTests {
    @Test("有未保存用户编辑时拒绝映射事务，不保存或回滚用户改动")
    func dirtyContextCannotBeCommittedByMapping() throws {
        let fixture = try makeFixture()
        fixture.occurrence.titleSnapshot = "尚未确认的编辑"
        var saves = 0
        let store = NotificationLinkStore(context: fixture.context, saveChanges: { _ in saves += 1 })
        #expect(throws: NotificationLinkStoreError.unsavedChanges) {
            try store.upsert(
                occurrenceID: fixture.occurrence.id, kind: .snooze,
                scheduledAt: fixture.occurrence.scheduledAt, submissionEpochUpdate: .replace(nil))
        }
        #expect(saves == 0 && fixture.context.hasChanges)
        #expect(fixture.occurrence.titleSnapshot == "尚未确认的编辑")
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 0)
    }

    @Test("映射保存失败不留下新世代或新时间，新槽位也不残留", arguments: [false, true], [false, true])
    func failedSavePreservesOriginalEpoch(existing: Bool, disk: Bool) throws {
        let url = disk ? try V0MigrationFixture.temporaryStoreURL() : nil
        let fixture = try makeFixture(storeURL: url)
        let now = fixture.occurrence.scheduledAt
        if existing {
            _ = try fixture.store.upsert(
                occurrenceID: fixture.occurrence.id, kind: .snooze,
                scheduledAt: now, createdAt: now, submissionEpochUpdate: .replace(V4MigrationFixture.returnedID))
        }
        let failing = NotificationLinkStore(
            context: fixture.context, saveChanges: { _ in throw CocoaError(.fileWriteUnknown) })
        #expect(throws: CocoaError.self) {
            try failing.upsert(
                occurrenceID: fixture.occurrence.id, kind: .snooze,
                scheduledAt: now.addingTimeInterval(600), submissionEpochUpdate: .replace(V4MigrationFixture.approvedID)
            )
        }
        let links = try fixture.store.links(occurrenceID: fixture.occurrence.id)
        #expect(links.count == (existing ? 1 : 0))
        if existing {
            let link = try #require(links.first)
            #expect(link.submissionIDAtScheduling == V4MigrationFixture.returnedID && link.scheduledAt == now)
            #expect(link.createdAt == now && link.occurrence?.id == fixture.occurrence.id)
        }
        #expect(!fixture.context.hasChanges)
        if let url {
            let reopened = ModelContext(try AppModelContainer.make(storeURL: url))
            let persisted = try NotificationLinkStore(context: reopened).links(occurrenceID: fixture.occurrence.id)
            #expect(persisted.count == (existing ? 1 : 0))
            if existing {
                let link = try #require(persisted.first)
                #expect(link.submissionIDAtScheduling == V4MigrationFixture.returnedID && link.scheduledAt == now)
            }
        }
    }

    @Test("普通核对保留世代，显式替换可设新 ID 或明确清空，首次时间和标识不变")
    func epochUpdateDistinguishesPreservingFromExplicitNil() throws {
        let fixture = try makeFixture()
        let now = fixture.occurrence.scheduledAt
        let id = V4MigrationFixture.returnedID
        let first = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id, kind: .snooze,
            scheduledAt: now, createdAt: now, submissionEpochUpdate: .replace(id))
        let identifier = first.requestIdentifier
        let retained = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id, kind: .snooze,
            scheduledAt: now.addingTimeInterval(60), createdAt: now.addingTimeInterval(60))
        #expect(retained.submissionIDAtScheduling == id && retained.createdAt == now)
        let cleared = try fixture.store.upsert(
            occurrenceID: fixture.occurrence.id, kind: .snooze,
            scheduledAt: now.addingTimeInterval(120), submissionEpochUpdate: .replace(nil))
        #expect(cleared.submissionIDAtScheduling == nil && cleared.createdAt == now)
        #expect(cleared.requestIdentifier == identifier)
        #expect(try fixture.store.links(occurrenceID: fixture.occurrence.id).count == 1)
    }

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

    private func makeFixture(storeURL: URL? = nil) throws -> Fixture {
        let container: ModelContainer
        if let storeURL {
            container = try AppModelContainer.make(storeURL: storeURL)
        } else {
            container = try AppModelContainer.make(inMemory: true)
        }
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
