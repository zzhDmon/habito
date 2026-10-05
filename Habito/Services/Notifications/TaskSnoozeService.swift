import Foundation
import OSLog
import SwiftData

/// 为当天未完成任务创建唯一的十分钟稍后提醒。
///
/// 系统通知和 SwiftData 映射通过同一个稳定 identifier 关联。同一任务再次操作时，
/// `UNUserNotificationCenter` 会以相同 identifier 替换旧请求，而不是累计多个提醒。
@MainActor
struct TaskSnoozeService {
    static let delay: TimeInterval = 10 * 60
    static let maximumPendingCount = 8

    private let context: ModelContext
    private let scheduler: any NotificationRequestScheduling
    private let permissionProvider: any NotificationPermissionProviding
    private let operationGate: NotificationOperationGate
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "TaskSnooze")
    private var calendar: Calendar
    private let timeZone: TimeZone

    init(
        context: ModelContext,
        scheduler: any NotificationRequestScheduling,
        permissionProvider: any NotificationPermissionProviding,
        calendar: Calendar,
        timeZone: TimeZone,
        operationGate: NotificationOperationGate = NotificationOperationGate()
    ) {
        self.context = context
        self.scheduler = scheduler
        self.permissionProvider = permissionProvider
        self.operationGate = operationGate
        self.calendar = calendar
        self.timeZone = timeZone
        self.calendar.timeZone = timeZone
    }

    /// 从操作时刻固定延后十分钟，并在成功写入系统请求后保存可审计映射。
    ///
    /// - Parameters:
    ///   - occurrenceID: 当前任务实例的稳定 ID。
    ///   - now: 用户操作时刻，由调用方注入以便测试午夜与预算边界。
    /// - Returns: 实际安排的绝对触发时间。
    /// - Throws: 任务不是今天、已经处理、跨本地午夜、提醒不可用、预算已满或系统排程失败时抛错。
    func schedule(occurrenceID: UUID, at now: Date) async throws -> Date {
        try await operationGate.perform {
            try await scheduleExclusively(occurrenceID: occurrenceID, at: now)
        }
    }

    private func scheduleExclusively(occurrenceID: UUID, at now: Date) async throws -> Date {
        let occurrence = try fetchOccurrence(id: occurrenceID)
        try validateStatus(of: occurrence)
        try Task.checkCancellation()

        let today = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
        let occurrenceDate: LocalDate
        do {
            occurrenceDate = try LocalDate(dateKey: occurrence.dateKey)
        } catch {
            throw TaskSnoozeError.invalidOccurrenceDate(occurrence.id, occurrence.dateKey)
        }
        guard occurrenceDate == today else {
            throw TaskSnoozeError.occurrenceIsNotToday(occurrence.id)
        }

        let scheduledAt = now.addingTimeInterval(Self.delay)
        let scheduledDate = try LocalDate(
            date: scheduledAt,
            calendar: calendar,
            timeZone: timeZone
        )
        guard scheduledDate == today else {
            throw TaskSnoozeError.crossesLocalMidnight
        }

        // 系统接受请求并不代表提醒会显示；孩子端不能把关闭权限当作安排成功。
        let permissions = await permissionProvider.diagnostics()
        guard permissions.canPresentAlerts else {
            throw TaskSnoozeError.notificationsUnavailable
        }

        let identifier = NotificationRequestIdentifier(
            occurrenceID: occurrenceID,
            kind: .snooze
        )
        let occupiedIdentifiers = try await occupiedSnoozeIdentifiers(
            excluding: identifier.rawValue,
            at: now
        )
        guard occupiedIdentifiers.count < Self.maximumPendingCount else {
            throw TaskSnoozeError.pendingLimitReached(Self.maximumPendingCount)
        }

        try Task.checkCancellation()
        // 预算读取也会让出执行权；权限可能已关闭，不能依赖旧快照先添加再取消。
        let permissionsBeforeAdding = await permissionProvider.diagnostics()
        try Task.checkCancellation()
        guard permissionsBeforeAdding.canPresentAlerts else {
            throw TaskSnoozeError.notificationsUnavailable
        }
        // 已删除的 SwiftData 对象仍可能保留缓存属性；必须按稳定 ID 重查，不能以旧对象状态证明实例存在。
        let latestOccurrence = try fetchOccurrence(id: occurrenceID)
        try validateStatus(of: latestOccurrence)
        let request = TaskNotificationRequest(
            occurrenceID: occurrenceID,
            kind: .snooze,
            title: latestOccurrence.titleSnapshot,
            body: String(localized: "notification.snoozeBody"),
            scheduledAt: scheduledAt
        )
        try await scheduler.addNotificationRequest(request)

        do {
            // 添加请求期间仍可能完成或删除任务；重新查询，避免复活已处理实例的提醒。
            try Task.checkCancellation()
            let latestPermissions = await permissionProvider.diagnostics()
            try Task.checkCancellation()
            // 系统 add 成功不保证权限仍有效；在保存映射前复核，失败沿用统一取消补偿。
            guard latestPermissions.canPresentAlerts else { throw TaskSnoozeError.notificationsUnavailable }
            try validateStatus(of: fetchOccurrence(id: occurrenceID))
            try NotificationLinkStore(context: context).upsert(
                occurrenceID: occurrenceID,
                kind: .snooze,
                scheduledAt: scheduledAt,
                createdAt: now
            )
        } catch {
            // 系统请求已成功但映射失败时立即移除，避免留下无法审计和清理的孤立提醒。
            do {
                try await scheduler.removePendingNotificationRequest(identifier: request.identifier)
            } catch {
                logger.error("稍后提醒补偿清理失败：\(String(describing: type(of: error)), privacy: .public)")
            }
            throw error
        }
        return scheduledAt
    }

    private func fetchOccurrence(id: UUID) throws -> TaskOccurrence {
        let descriptor = FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == id })
        guard let occurrence = try context.fetch(descriptor).first else {
            throw TaskSnoozeError.occurrenceNotFound(id)
        }
        return occurrence
    }

    private func validateStatus(of occurrence: TaskOccurrence) throws {
        // 所有 await 后的复核共用此等待保护，避免提交期间稍后请求被复活。
        try TaskSubmissionHistory(context: context).requireNotWaiting(occurrence.id)
        guard let status = occurrence.status else {
            throw TaskSnoozeError.invalidOccurrenceStatus(
                occurrence.id,
                occurrence.statusRawValue
            )
        }
        guard status == .pending || status == .inProgress else {
            throw TaskSnoozeError.invalidOccurrenceStatus(occurrence.id, status.rawValue)
        }
    }

    private func occupiedSnoozeIdentifiers(
        excluding excludedIdentifier: String,
        at now: Date
    ) async throws -> Set<String> {
        let pendingIdentifiers: [String] = try await scheduler.pendingNotificationRequests().compactMap { snapshot in
            guard
                snapshot.identifier != excludedIdentifier,
                let identifier = NotificationRequestIdentifier(rawValue: snapshot.identifier),
                identifier.kind == .snooze
            else {
                return nil
            }
            return snapshot.identifier
        }
        var identifiers = Set<String>(pendingIdentifiers)

        // 系统快照可能延迟反映已写入映射；即使系统暂未返回，也保留该槽位的预算占用。
        for link in try context.fetch(FetchDescriptor<NotificationLink>())
        where link.requestIdentifier != excludedIdentifier && link.scheduledAt > now {
            guard
                let identifier = NotificationRequestIdentifier(rawValue: link.requestIdentifier),
                identifier.kind == .snooze
            else {
                continue
            }
            identifiers.insert(link.requestIdentifier)
        }
        return identifiers
    }
}
