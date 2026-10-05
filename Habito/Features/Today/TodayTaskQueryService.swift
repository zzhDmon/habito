import Foundation
import SwiftData

/// 从 SwiftData 生成孩子今日页可直接消费的只读快照。
///
/// 查询运行在主 actor，避免持久化模型跨并发域传递。调用方显式提供日期和当前时间；
/// 日历与时区由组合根注入，因此测试不会依赖设备设置或真实时钟。
@MainActor
struct TodayTaskQueryService {
    private let context: ModelContext
    private var calendar: Calendar
    private let timeZone: TimeZone

    init(context: ModelContext, calendar: Calendar, timeZone: TimeZone) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.calendar.timeZone = timeZone
    }

    /// 查询指定本地日期，并按“正在进行、已到点、即将开始、其余”排序。
    ///
    /// - Parameters:
    ///   - date: 需要展示的本地日期。
    ///   - now: 排序和运行中时长计算使用的绝对当前时间。
    /// - Returns: 不持有 SwiftData 模型的今日快照。
    /// - Throws: 存储原始值损坏或实例、计时、完成关系不一致时抛出
    ///   `TodayTaskQueryError`；底层读取失败时透传 SwiftData 错误。
    func snapshot(for date: LocalDate, at now: Date) throws -> TodayTasksSnapshot {
        let dateKey = date.dateKey
        let descriptor = FetchDescriptor<TaskOccurrence>(
            predicate: #Predicate { $0.dateKey == dateKey }
        )
        let items = try context.fetch(descriptor).map { occurrence in
            try makeItem(from: occurrence, at: now)
        }
        let sortedItems = items.sorted { lhs, rhs in
            sortKey(for: lhs, at: now) < sortKey(for: rhs, at: now)
        }
        let carryOverItems = try carryOverItems(before: date, at: now)
        let actionable = (carryOverItems + sortedItems).first { item in
            item.status == .inProgress || item.status == .pending
        }
        let visibleItems = sortedItems.filter { $0.status != .skipped }
        let currentDate = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)

        return TodayTasksSnapshot(
            date: date,
            isCurrentDate: currentDate == date,
            tasks: sortedItems,
            carryOverTasks: carryOverItems,
            recommendedTaskID: actionable?.id,
            completedCount: visibleItems.count { $0.status == .completed },
            totalCount: visibleItems.count
        )
    }

    /// 找出目标日期之前仍有活动会话的实例，避免跨午夜后从孩子界面消失。
    private func carryOverItems(before date: LocalDate, at now: Date) throws -> [TodayTaskItem] {
        let inProgress = TaskOccurrenceStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<TaskOccurrence>(
            predicate: #Predicate { $0.statusRawValue == inProgress },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        return try context.fetch(descriptor)
            .filter { $0.dateKey < date.dateKey }
            .map { try makeItem(from: $0, at: now) }
    }

    /// 按稳定实例 ID 读取单个任务，供任务执行页重进或前台恢复时刷新。
    ///
    /// - Parameters:
    ///   - id: `TaskOccurrence` 的稳定标识。
    ///   - now: 运行中时长计算使用的绝对当前时间。
    /// - Returns: 不持有 SwiftData 模型的任务页面值。
    /// - Throws: 实例不存在或存储关系不满足领域约束时抛出明确错误。
    func item(id: UUID, at now: Date) throws -> TodayTaskItem {
        let descriptor = FetchDescriptor<TaskOccurrence>(
            predicate: #Predicate { $0.id == id }
        )
        guard let occurrence = try context.fetch(descriptor).first else {
            throw TodayTaskQueryError.occurrenceNotFound(occurrenceID: id)
        }
        return try makeItem(from: occurrence, at: now)
    }

    private func makeItem(from occurrence: TaskOccurrence, at now: Date) throws -> TodayTaskItem {
        let date: LocalDate
        do {
            date = try LocalDate(dateKey: occurrence.dateKey)
        } catch {
            throw TodayTaskQueryError.invalidOccurrenceDate(
                occurrenceID: occurrence.id,
                value: occurrence.dateKey
            )
        }
        guard let status = occurrence.status else {
            throw TodayTaskQueryError.invalidOccurrenceStatus(
                occurrenceID: occurrence.id,
                value: occurrence.statusRawValue
            )
        }
        guard occurrence.targetDurationSnapshot > 0 else {
            throw TodayTaskQueryError.invalidTargetDuration(
                occurrenceID: occurrence.id,
                value: occurrence.targetDurationSnapshot
            )
        }

        let sessions = try sessions(for: occurrence, at: now)
        let activeSessions = sessions.filter { $0.state != .ended }
        guard activeSessions.count <= 1 else {
            throw TodayTaskQueryError.multipleActiveSessions(occurrenceID: occurrence.id)
        }
        let completion = try completion(for: occurrence)
        try validateRelations(
            status: status,
            activeSessionCount: activeSessions.count,
            hasCompletion: completion != nil,
            occurrenceID: occurrence.id
        )

        let sessionDuration = sessions.reduce(0) { $0 + $1.duration }
        let displayedDuration = completion?.activeDurationSeconds ?? sessionDuration

        return TodayTaskItem(
            id: occurrence.id,
            date: date,
            scheduledAt: occurrence.scheduledAt,
            title: occurrence.titleSnapshot,
            iconName: occurrence.iconSnapshot,
            colorToken: occurrence.colorSnapshot,
            targetDurationSeconds: occurrence.targetDurationSnapshot,
            status: status,
            origin: occurrence.origin,
            activeSessionState: activeSessions.first?.state,
            activeDurationSeconds: displayedDuration,
            completion: completion
        )
    }

    private func sessions(
        for occurrence: TaskOccurrence,
        at now: Date
    ) throws -> [(state: TimerSessionState, duration: TimeInterval)] {
        let occurrenceID = occurrence.id
        let descriptor = FetchDescriptor<TimerSession>(
            predicate: #Predicate { $0.occurrenceID == occurrenceID }
        )
        return try context.fetch(descriptor).map { session in
            guard let state = session.state else {
                throw TodayTaskQueryError.invalidSessionState(
                    sessionID: session.id,
                    value: session.stateRawValue
                )
            }
            guard session.accumulatedActiveSeconds >= 0 else {
                throw TodayTaskQueryError.negativeSessionDuration(
                    sessionID: session.id,
                    value: session.accumulatedActiveSeconds
                )
            }
            guard session.lastResumedAt >= session.startedAt else {
                throw TodayTaskQueryError.invalidSessionTimeline(sessionID: session.id)
            }

            let duration: TimeInterval
            switch state {
            case .running:
                guard session.endedAt == nil, now >= session.lastResumedAt else {
                    throw TodayTaskQueryError.invalidSessionTimeline(sessionID: session.id)
                }
                duration =
                    session.accumulatedActiveSeconds
                    + now.timeIntervalSince(session.lastResumedAt)
            case .paused:
                guard session.endedAt == nil, now >= session.startedAt else {
                    throw TodayTaskQueryError.invalidSessionTimeline(sessionID: session.id)
                }
                duration = session.accumulatedActiveSeconds
            case .ended:
                guard let endedAt = session.endedAt,
                    endedAt >= session.lastResumedAt,
                    now >= endedAt
                else {
                    throw TodayTaskQueryError.invalidSessionTimeline(sessionID: session.id)
                }
                duration = session.accumulatedActiveSeconds
            }
            return (state, duration)
        }
    }

    private func completion(for occurrence: TaskOccurrence) throws -> TodayTaskCompletion? {
        let occurrenceID = occurrence.id
        let descriptor = FetchDescriptor<CompletionRecord>(
            predicate: #Predicate { $0.occurrenceID == occurrenceID && $0.revokedAt == nil }
        )
        let records = try context.fetch(descriptor)
        guard records.count <= 1 else {
            throw TodayTaskQueryError.multipleCompletionRecords(occurrenceID: occurrence.id)
        }
        guard let record = records.first else { return nil }
        guard let source = record.completionSource else {
            throw TodayTaskQueryError.invalidCompletionSource(
                occurrenceID: occurrence.id,
                value: record.completionSourceRawValue
            )
        }
        guard record.activeDurationSeconds >= 0 else {
            throw TodayTaskQueryError.negativeCompletionDuration(
                occurrenceID: occurrence.id,
                value: record.activeDurationSeconds
            )
        }
        return TodayTaskCompletion(
            id: record.id,
            completedAt: record.completedAt,
            activeDurationSeconds: record.activeDurationSeconds,
            source: source
        )
    }

    private func validateRelations(
        status: TaskOccurrenceStatus,
        activeSessionCount: Int,
        hasCompletion: Bool,
        occurrenceID: UUID
    ) throws {
        switch status {
        case .inProgress:
            guard activeSessionCount == 1 else {
                throw TodayTaskQueryError.missingActiveSession(occurrenceID: occurrenceID)
            }
            guard !hasCompletion else {
                throw TodayTaskQueryError.unexpectedCompletionRecord(occurrenceID: occurrenceID)
            }
        case .completed:
            guard activeSessionCount == 0 else {
                throw TodayTaskQueryError.unexpectedActiveSession(occurrenceID: occurrenceID)
            }
            guard hasCompletion else {
                throw TodayTaskQueryError.missingCompletionRecord(occurrenceID: occurrenceID)
            }
        case .pending, .skipped:
            guard activeSessionCount == 0 else {
                throw TodayTaskQueryError.unexpectedActiveSession(occurrenceID: occurrenceID)
            }
            guard !hasCompletion else {
                throw TodayTaskQueryError.unexpectedCompletionRecord(occurrenceID: occurrenceID)
            }
        }
    }

    private func sortKey(
        for item: TodayTaskItem,
        at now: Date
    ) -> (Int, Date, String) {
        let rank: Int
        switch item.status {
        case .inProgress:
            rank = 0
        case .pending where item.scheduledAt <= now:
            rank = 1
        case .pending:
            rank = 2
        case .completed:
            rank = 3
        case .skipped:
            rank = 4
        }
        return (rank, item.scheduledAt, item.id.uuidString)
    }
}
