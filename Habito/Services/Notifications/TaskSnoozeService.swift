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
    private let operationGate: NotificationOperationGate
    private let logger = Logger(subsystem: "com.zhangzehua.Habito", category: "TaskSnooze")
    private var calendar: Calendar
    private let timeZone: TimeZone

    init(
        context: ModelContext,
        scheduler: any NotificationRequestScheduling,
        calendar: Calendar,
        timeZone: TimeZone,
        operationGate: NotificationOperationGate = NotificationOperationGate()
    ) {
        self.context = context
        self.scheduler = scheduler
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
    /// - Throws: 任务不是今天、已经处理、跨本地午夜、预算已满或系统排程失败时抛错。
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

        let identifier = NotificationRequestIdentifier(
            occurrenceID: occurrence.id,
            kind: .snooze
        )
        let occupiedIdentifiers = try await occupiedSnoozeIdentifiers(
            excluding: identifier.rawValue,
            at: now
        )
        guard occupiedIdentifiers.count < Self.maximumPendingCount else {
            throw TaskSnoozeError.pendingLimitReached(Self.maximumPendingCount)
        }

        // `pendingNotificationRequests()` 是异步系统边界；返回后重新核对状态，降低等待期间完成任务的竞态窗口。
        try validateStatus(of: occurrence)
        let request = TaskNotificationRequest(
            occurrenceID: occurrence.id,
            kind: .snooze,
            title: occurrence.titleSnapshot,
            body: String(localized: "notification.snoozeBody"),
            scheduledAt: scheduledAt
        )
        try await scheduler.addNotificationRequest(request)

        do {
            // 添加请求期间仍可能完成或删除任务；重新查询，避免复活已处理实例的提醒。
            try Task.checkCancellation()
            try validateStatus(of: fetchOccurrence(id: occurrenceID))
            try NotificationLinkStore(context: context).upsert(
                occurrenceID: occurrence.id,
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
