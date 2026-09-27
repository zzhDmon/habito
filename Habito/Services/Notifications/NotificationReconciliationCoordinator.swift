import Foundation

/// 将 Habito 期望通知与系统挂起请求做增量核对。
///
/// 只有能解析为 `NotificationRequestIdentifier` 的请求属于本协调器；探针和其他来源请求不会被删除。
@MainActor
struct NotificationReconciliationCoordinator {
    private let scheduler: any NotificationRequestScheduling

    init(scheduler: any NotificationRequestScheduling) {
        self.scheduler = scheduler
    }

    /// 取消过期请求、保留完全一致请求，并逐条新增或替换变化请求。
    ///
    /// - Parameter desiredRequests: 当前业务状态推导出的完整期望集合。
    /// - Returns: 每类变更和单条失败的确定性报告。
    func reconcile(
        desiredRequests: [TaskNotificationRequest]
    ) async -> NotificationReconciliationReport {
        var report = NotificationReconciliationReport()
        let desiredByIdentifier = validatedDesiredRequests(desiredRequests, report: &report)

        let pendingRequests: [PendingNotificationRequestSnapshot]
        do {
            pendingRequests = try await scheduler.pendingNotificationRequests()
        } catch {
            report.failures.append(
                NotificationReconciliationFailure(
                    identifier: nil,
                    operation: .readPending,
                    message: String(describing: error)
                )
            )
            return report
        }

        var managedPending: [String: PendingNotificationRequestSnapshot] = [:]
        for request in pendingRequests
        where NotificationRequestIdentifier(rawValue: request.identifier) != nil {
            managedPending[request.identifier] = request
        }

        for identifier in managedPending.keys.sorted() where desiredByIdentifier[identifier] == nil {
            await remove(identifier: identifier, operation: .remove, report: &report)
        }

        for identifier in desiredByIdentifier.keys.sorted() {
            guard let desired = desiredByIdentifier[identifier] else { continue }

            guard let pending = managedPending[identifier] else {
                await add(desired, operation: .add, report: &report)
                continue
            }

            if matches(pending: pending, desired: desired) {
                report.retainedIdentifiers.append(identifier)
                continue
            }

            await replace(pendingIdentifier: identifier, with: desired, report: &report)
        }

        return report
    }

    private func validatedDesiredRequests(
        _ requests: [TaskNotificationRequest],
        report: inout NotificationReconciliationReport
    ) -> [String: TaskNotificationRequest] {
        var result: [String: TaskNotificationRequest] = [:]
        for request in requests {
            if result.updateValue(request, forKey: request.identifier) != nil {
                report.failures.append(
                    NotificationReconciliationFailure(
                        identifier: request.identifier,
                        operation: .validateDesired,
                        message: "Duplicate desired notification identifier"
                    )
                )
            }
        }
        return result
    }

    private func matches(
        pending: PendingNotificationRequestSnapshot,
        desired: TaskNotificationRequest
    ) -> Bool {
        guard let pendingDate = pending.scheduledAt else { return false }
        return pending.title == desired.title
            && pending.body == desired.body
            && abs(pendingDate.timeIntervalSince(desired.scheduledAt)) < 1
    }

    private func remove(
        identifier: String,
        operation: NotificationReconciliationFailure.Operation,
        report: inout NotificationReconciliationReport
    ) async {
        do {
            try await scheduler.removePendingNotificationRequest(identifier: identifier)
            report.removedIdentifiers.append(identifier)
        } catch {
            report.failures.append(
                NotificationReconciliationFailure(
                    identifier: identifier,
                    operation: operation,
                    message: String(describing: error)
                )
            )
        }
    }

    private func add(
        _ request: TaskNotificationRequest,
        operation: NotificationReconciliationFailure.Operation,
        report: inout NotificationReconciliationReport
    ) async {
        do {
            try await scheduler.addNotificationRequest(request)
            report.addedIdentifiers.append(request.identifier)
        } catch {
            report.failures.append(
                NotificationReconciliationFailure(
                    identifier: request.identifier,
                    operation: operation,
                    message: String(describing: error)
                )
            )
        }
    }

    private func replace(
        pendingIdentifier: String,
        with desired: TaskNotificationRequest,
        report: inout NotificationReconciliationReport
    ) async {
        do {
            try await scheduler.removePendingNotificationRequest(identifier: pendingIdentifier)
            try await scheduler.addNotificationRequest(desired)
            report.replacedIdentifiers.append(pendingIdentifier)
        } catch {
            report.failures.append(
                NotificationReconciliationFailure(
                    identifier: pendingIdentifier,
                    operation: .replace,
                    message: String(describing: error)
                )
            )
        }
    }
}
