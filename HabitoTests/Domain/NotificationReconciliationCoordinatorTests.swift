import Foundation
import Testing
@testable import Habito

@MainActor
struct NotificationReconciliationCoordinatorTests {
    @Test("相同集合连续核对五次只在首次添加")
    func fiveRunsAreIdempotent() async {
        let scheduler = FakeNotificationRequestScheduler()
        let coordinator = NotificationReconciliationCoordinator(scheduler: scheduler)
        let requests = [request(index: 1), request(index: 2)]

        var reports: [NotificationReconciliationReport] = []
        for _ in 0..<5 {
            reports.append(await coordinator.reconcile(desiredRequests: requests))
        }

        #expect(scheduler.addedIdentifiers == requests.map(\.identifier))
        #expect(scheduler.pending.count == 2)
        #expect(reports[0].addedIdentifiers == requests.map(\.identifier).sorted())
        #expect(reports.dropFirst().allSatisfy { $0.retainedIdentifiers.count == 2 })
        #expect(reports.allSatisfy { $0.isSuccessful })
    }

    @Test("只增量替换变化请求并保留非 Habito 通知")
    func reconcilesDifferenceWithoutTouchingForeignRequests() async {
        let unchanged = request(index: 1)
        let changed = request(index: 2)
        let stale = request(index: 3)
        let added = request(index: 4)
        let foreign = PendingNotificationRequestSnapshot(
            identifier: LocalNotificationService.probeIdentifier,
            title: "probe",
            body: "probe",
            scheduledAt: changed.scheduledAt
        )
        let scheduler = FakeNotificationRequestScheduler(
            pending: [
                snapshot(unchanged),
                PendingNotificationRequestSnapshot(
                    identifier: changed.identifier,
                    title: "old title",
                    body: changed.body,
                    scheduledAt: changed.scheduledAt
                ),
                snapshot(stale),
                foreign,
            ]
        )
        let coordinator = NotificationReconciliationCoordinator(scheduler: scheduler)

        let report = await coordinator.reconcile(
            desiredRequests: [unchanged, changed, added]
        )

        #expect(report.retainedIdentifiers == [unchanged.identifier])
        #expect(report.replacedIdentifiers == [changed.identifier])
        #expect(report.removedIdentifiers == [stale.identifier])
        #expect(report.addedIdentifiers == [added.identifier])
        #expect(scheduler.pending[foreign.identifier] == foreign)
        #expect(scheduler.pending.count == 4)
        #expect(report.isSuccessful)
    }

    @Test("单条新增失败会记录且不阻断其他请求")
    func oneFailureDoesNotBreakOtherRequests() async {
        let retained = request(index: 1)
        let failing = request(index: 2)
        let added = request(index: 3)
        let stale = request(index: 4)
        let scheduler = FakeNotificationRequestScheduler(
            pending: [snapshot(retained), snapshot(stale)]
        )
        scheduler.failingAddIdentifiers = [failing.identifier]
        let coordinator = NotificationReconciliationCoordinator(scheduler: scheduler)

        let report = await coordinator.reconcile(
            desiredRequests: [retained, failing, added]
        )

        #expect(report.retainedIdentifiers == [retained.identifier])
        #expect(report.addedIdentifiers == [added.identifier])
        #expect(report.removedIdentifiers == [stale.identifier])
        #expect(report.failures.count == 1)
        #expect(report.failures[0].identifier == failing.identifier)
        #expect(report.failures[0].operation == .add)
        #expect(scheduler.pending[retained.identifier] != nil)
        #expect(scheduler.pending[added.identifier] != nil)
        #expect(scheduler.pending[failing.identifier] == nil)
        #expect(scheduler.pending[stale.identifier] == nil)
    }

    @Test("已送达的失效 Habito 通知被清理，探针保持隔离")
    func deliveredCleanupIsScopedAndIdempotent() async {
        let desired = request(index: 1)
        let stale = request(index: 2)
        let orphan = request(index: 3)
        let scheduler = FakeNotificationRequestScheduler()
        scheduler.delivered = [
            desired.identifier, stale.identifier, orphan.identifier, LocalNotificationService.probeIdentifier,
        ]
        let coordinator = NotificationReconciliationCoordinator(scheduler: scheduler)

        let first = await coordinator.reconcile(desiredRequests: [desired])
        let second = await coordinator.reconcile(desiredRequests: [desired])

        #expect(first.removedDeliveredIdentifiers == [stale.identifier, orphan.identifier].sorted())
        #expect(second.removedDeliveredIdentifiers.isEmpty)
        #expect(scheduler.delivered == [desired.identifier, LocalNotificationService.probeIdentifier])
        #expect(first.isSuccessful && second.isSuccessful)
    }

    @Test("单条已送达清理失败可重试且不阻断其他清理")
    func deliveredCleanupFailureCanRetry() async {
        let failing = request(index: 1)
        let removable = request(index: 2)
        let scheduler = FakeNotificationRequestScheduler()
        scheduler.delivered = [failing.identifier, removable.identifier]
        scheduler.failingDeliveredRemovalIdentifiers = [failing.identifier]
        let coordinator = NotificationReconciliationCoordinator(scheduler: scheduler)

        let first = await coordinator.reconcile(desiredRequests: [])
        #expect(first.removedDeliveredIdentifiers == [removable.identifier])
        #expect(first.failures.first?.operation == .removeDelivered)
        #expect(scheduler.delivered == [failing.identifier])
        scheduler.failingDeliveredRemovalIdentifiers = []
        let retried = await coordinator.reconcile(desiredRequests: [])
        #expect(retried.isSuccessful)
        #expect(scheduler.delivered.isEmpty)
    }

    private func request(index: UInt8) -> TaskNotificationRequest {
        TaskNotificationRequest(
            occurrenceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, index)),
            kind: .primary,
            title: "Task \(index)",
            body: "Start now",
            scheduledAt: Date(timeIntervalSince1970: 2_000_000_000 + Double(index * 60))
        )
    }

    private func snapshot(_ request: TaskNotificationRequest) -> PendingNotificationRequestSnapshot {
        PendingNotificationRequestSnapshot(
            identifier: request.identifier,
            title: request.title,
            body: request.body,
            scheduledAt: request.scheduledAt
        )
    }
}

@MainActor
private final class FakeNotificationRequestScheduler: NotificationRequestScheduling {
    enum Failure: Error {
        case requested
    }

    var pending: [String: PendingNotificationRequestSnapshot]
    var failingAddIdentifiers: Set<String> = []
    var addedIdentifiers: [String] = []
    var delivered: Set<String> = []
    var failingDeliveredRemovalIdentifiers: Set<String> = []

    init(pending: [PendingNotificationRequestSnapshot] = []) {
        self.pending = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
    }

    func pendingNotificationRequests() async throws -> [PendingNotificationRequestSnapshot] {
        Array(pending.values)
    }

    func addNotificationRequest(_ request: TaskNotificationRequest) async throws {
        guard !failingAddIdentifiers.contains(request.identifier) else {
            throw Failure.requested
        }
        addedIdentifiers.append(request.identifier)
        pending[request.identifier] = PendingNotificationRequestSnapshot(
            identifier: request.identifier,
            title: request.title,
            body: request.body,
            scheduledAt: request.scheduledAt
        )
    }

    func removePendingNotificationRequest(identifier: String) async throws {
        pending[identifier] = nil
    }

    func deliveredNotificationIdentifiers() async throws -> [String] { Array(delivered) }

    func removeDeliveredNotificationRequest(identifier: String) async throws {
        if failingDeliveredRemovalIdentifiers.contains(identifier) { throw Failure.requested }
        delivered.remove(identifier)
    }
}
