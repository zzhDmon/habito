import Foundation
import SwiftData
import Testing
@testable import Habito

@Suite("通知点击路由")
@MainActor
struct NotificationNavigationServiceTests {
    @Test(
        "待处理或进行中的实例进入任务页",
        arguments: [TaskOccurrenceStatus.pending, .inProgress]
    )
    func activeOccurrenceRoutesToTask(status: TaskOccurrenceStatus) throws {
        let fixture = try Fixture()
        let occurrence = try fixture.insertOccurrence(status: status)

        let destination = fixture.service.destination(
            for: fixture.identifier(for: occurrence.id)
        )

        #expect(destination == .task(occurrence.id))
    }

    @Test(
        "已处理实例安全回首页",
        arguments: [TaskOccurrenceStatus.completed, .skipped]
    )
    func processedOccurrenceRoutesHome(status: TaskOccurrenceStatus) throws {
        let fixture = try Fixture()
        let occurrence = try fixture.insertOccurrence(status: status)

        #expect(fixture.service.destination(for: fixture.identifier(for: occurrence.id)) == .home)
    }

    @Test("已删除实例安全回首页")
    func deletedOccurrenceRoutesHome() throws {
        let fixture = try Fixture()
        #expect(fixture.service.destination(for: fixture.identifier(for: UUID())) == .home)
    }

    @Test("非 Habito 或损坏标识不干扰当前页面")
    func foreignIdentifierIsIgnored() throws {
        let fixture = try Fixture()
        #expect(fixture.service.destination(for: "habito.probe") == .ignored)
        #expect(fixture.service.destination(for: "habito.occurrence.bad.primary") == .ignored)
    }

    @Test("点击桥在根视图创建前保留并只消费一次标识")
    func responseRouterBuffersColdLaunchIntent() {
        let router = NotificationResponseRouter()
        router.receive(requestIdentifier: "request-id")

        #expect(router.revision == 1)
        #expect(router.consumePendingRequestIdentifier() == "request-id")
        #expect(router.consumePendingRequestIdentifier() == nil)
    }
}

@MainActor
private extension NotificationNavigationServiceTests {
    final class Fixture {
        let context: ModelContext
        let service: NotificationNavigationService

        init() throws {
            context = ModelContext(try AppModelContainer.make(inMemory: true))
            service = NotificationNavigationService(context: context)
        }

        func insertOccurrence(status: TaskOccurrenceStatus) throws -> TaskOccurrence {
            let occurrence = TaskOccurrence(
                templateID: UUID(),
                date: try LocalDate(dateKey: "2026-09-27"),
                scheduledAt: try Date("2026-09-27T11:30:00Z", strategy: .iso8601),
                titleSnapshot: "阅读",
                iconSnapshot: "book.fill",
                colorSnapshot: "reading",
                targetDurationSnapshot: 900,
                status: status,
                sourceRevision: 1
            )
            context.insert(occurrence)
            try context.save()
            return occurrence
        }

        func identifier(for occurrenceID: UUID) -> String {
            NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: .primary).rawValue
        }
    }
}
