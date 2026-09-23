import Foundation
import SwiftData

/// 集中管理任务实例的计时会话与完成记录事务。
///
/// 服务运行在主 actor，保证 SwiftData 模型不会跨并发域共享。调用方必须注入每次
/// 操作的绝对时间；前后台恢复只需重新计算时间差，不依赖后台持续运行计时器。
@MainActor
struct TaskProgressService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 开始一个可计时任务；已有活动会话时直接返回，由暂停/继续方法改变其状态。
    func startTiming(for occurrence: TaskOccurrence, at now: Date) throws -> TimerSession {
        let status = try validatedStatus(of: occurrence)
        let sessions = try validatedSessions(for: occurrence)
        let active = try activeSession(in: sessions, occurrenceID: occurrence.id)

        if let active {
            guard status == .inProgress else {
                throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(
                    occurrenceID: occurrence.id
                )
            }
            return active.session
        }

        let nextStatus: TaskOccurrenceStatus
        if status == .inProgress {
            // 撤销完成或显式结束上一段后，可为同一任务创建新的计时段。
            nextStatus = .inProgress
        } else {
            nextStatus = try status.applying(.start)
        }

        let session = TimerSession(
            occurrenceID: occurrence.id,
            state: .running,
            startedAt: now,
            lastResumedAt: now
        )
        session.occurrence = occurrence
        context.insert(session)
        occurrence.statusRawValue = nextStatus.rawValue
        occurrence.updatedAt = now
        try context.save()
        return session
    }

    /// 暂停当前运行段；重复暂停不会再次累计时长。
    func pauseTiming(for occurrence: TaskOccurrence, at now: Date) throws -> TimerSession {
        try requireInProgress(occurrence)
        let active = try requireActiveSession(for: occurrence)
        if active.state == .paused { return active.session }

        let elapsed = try runningSegmentDuration(active.session, at: now)
        active.session.accumulatedActiveSeconds += elapsed
        active.session.stateRawValue = TimerSessionState.paused.rawValue
        occurrence.updatedAt = now
        try context.save()
        return active.session
    }

    /// 继续已暂停的会话；重复继续不会重置当前运行段起点。
    func resumeTiming(for occurrence: TaskOccurrence, at now: Date) throws -> TimerSession {
        try requireInProgress(occurrence)
        let active = try requireActiveSession(for: occurrence)
        if active.state == .running { return active.session }
        guard now >= active.session.startedAt else {
            throw TaskProgressServiceError.timeBeforeSessionStart(sessionID: active.session.id)
        }
        guard now >= active.session.lastResumedAt else {
            throw TaskProgressServiceError.timeBeforeLastResume(sessionID: active.session.id)
        }

        active.session.lastResumedAt = now
        active.session.stateRawValue = TimerSessionState.running.rawValue
        occurrence.updatedAt = now
        try context.save()
        return active.session
    }

    /// 结束当前会话但不自动完成任务，便于之后创建新的计时段。
    func endTiming(for occurrence: TaskOccurrence, at now: Date) throws -> TimerSession {
        try requireInProgress(occurrence)
        let active = try requireActiveSession(for: occurrence)
        let finalDuration = try activeDuration(of: active, at: now)

        active.session.accumulatedActiveSeconds = finalDuration
        active.session.stateRawValue = TimerSessionState.ended.rawValue
        active.session.endedAt = now
        occurrence.updatedAt = now
        try context.save()
        return active.session
    }

    /// 返回会话截至指定时刻的有效活动秒数。
    func activeDuration(of session: TimerSession, at now: Date) throws -> TimeInterval {
        let state = try validatedState(of: session)
        return try activeDuration(of: (session, state), at: now)
    }

    /// 完成任务并写入唯一完成记录；重复完成返回原记录。
    func complete(
        _ occurrence: TaskOccurrence,
        at now: Date,
        source: CompletionSource
    ) throws -> CompletionRecord {
        let status = try validatedStatus(of: occurrence)
        let sessions = try validatedSessions(for: occurrence)
        let active = try activeSession(in: sessions, occurrenceID: occurrence.id)
        let existingRecord = try completionRecord(for: occurrence)

        if status == .completed {
            guard active == nil else {
                throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(
                    occurrenceID: occurrence.id
                )
            }
            guard let existingRecord else {
                throw TaskProgressServiceError.completionRecordMissing(occurrenceID: occurrence.id)
            }
            return existingRecord
        }
        guard existingRecord == nil else {
            throw TaskProgressServiceError.unexpectedCompletionRecord(occurrenceID: occurrence.id)
        }
        let nextStatus = try status.applying(.complete)
        let totalDuration = try sessions.reduce(0) { partial, sessionState in
            partial + (try activeDuration(of: sessionState, at: now))
        }

        if let active {
            active.session.accumulatedActiveSeconds = try activeDuration(of: active, at: now)
            active.session.stateRawValue = TimerSessionState.ended.rawValue
            active.session.endedAt = now
        }

        let record = CompletionRecord(
            occurrenceID: occurrence.id,
            completedAt: now,
            activeDurationSeconds: totalDuration,
            completionSource: source,
            createdAt: now,
            updatedAt: now
        )
        occurrence.completionRecord = record
        occurrence.statusRawValue = nextStatus.rawValue
        occurrence.updatedAt = now
        context.insert(record)
        try context.save()
        return record
    }

    /// 撤销完成事实并把任务恢复为待处理；旧计时会话保持终态。
    @discardableResult
    func undoCompletion(of occurrence: TaskOccurrence, at now: Date) throws -> Bool {
        let status = try validatedStatus(of: occurrence)
        let sessions = try validatedSessions(for: occurrence)
        let active = try activeSession(in: sessions, occurrenceID: occurrence.id)
        guard active == nil else {
            throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(
                occurrenceID: occurrence.id
            )
        }

        let existingRecord = try completionRecord(for: occurrence)
        if status == .pending, existingRecord == nil {
            return false
        }
        if status == .pending, existingRecord != nil {
            throw TaskProgressServiceError.unexpectedCompletionRecord(occurrenceID: occurrence.id)
        }
        let nextStatus = try status.applying(.undoCompletion)
        guard let record = existingRecord else {
            throw TaskProgressServiceError.completionRecordMissing(occurrenceID: occurrence.id)
        }
        guard now >= record.completedAt else {
            throw TaskProgressServiceError.timeBeforeCompletion(occurrenceID: occurrence.id)
        }
        occurrence.completionRecord = nil
        occurrence.statusRawValue = nextStatus.rawValue
        occurrence.updatedAt = now
        context.delete(record)
        try context.save()
        return true
    }

    private typealias SessionState = (session: TimerSession, state: TimerSessionState)

    private func validatedStatus(of occurrence: TaskOccurrence) throws -> TaskOccurrenceStatus {
        guard let status = occurrence.status else {
            throw TaskProgressServiceError.invalidOccurrenceStatus(
                occurrenceID: occurrence.id,
                rawValue: occurrence.statusRawValue
            )
        }
        return status
    }

    private func validatedState(of session: TimerSession) throws -> TimerSessionState {
        guard let state = session.state else {
            throw TaskProgressServiceError.invalidSessionState(
                sessionID: session.id,
                rawValue: session.stateRawValue
            )
        }
        guard session.accumulatedActiveSeconds >= 0 else {
            throw TaskProgressServiceError.negativeAccumulatedDuration(sessionID: session.id)
        }
        return state
    }

    private func validatedSessions(for occurrence: TaskOccurrence) throws -> [SessionState] {
        let occurrenceID = occurrence.id
        let descriptor = FetchDescriptor<TimerSession>(
            predicate: #Predicate { $0.occurrenceID == occurrenceID }
        )
        return try context.fetch(descriptor).map { session in
            (session, try validatedState(of: session))
        }
    }

    private func completionRecord(for occurrence: TaskOccurrence) throws -> CompletionRecord? {
        let occurrenceID = occurrence.id
        let descriptor = FetchDescriptor<CompletionRecord>(
            predicate: #Predicate { $0.occurrenceID == occurrenceID }
        )
        let records = try context.fetch(descriptor)
        guard records.count <= 1 else {
            throw TaskProgressServiceError.multipleCompletionRecords(occurrenceID: occurrence.id)
        }
        return records.first
    }

    private func activeSession(
        in sessions: [SessionState],
        occurrenceID: UUID
    ) throws -> SessionState? {
        let active = sessions.filter { $0.state != .ended }
        guard active.count <= 1 else {
            throw TaskProgressServiceError.multipleActiveSessions(occurrenceID: occurrenceID)
        }
        return active.first
    }

    private func requireActiveSession(for occurrence: TaskOccurrence) throws -> SessionState {
        let sessions = try validatedSessions(for: occurrence)
        guard let active = try activeSession(in: sessions, occurrenceID: occurrence.id) else {
            throw TaskProgressServiceError.noActiveSession(occurrenceID: occurrence.id)
        }
        return active
    }

    private func requireInProgress(_ occurrence: TaskOccurrence) throws {
        let status = try validatedStatus(of: occurrence)
        guard status == .inProgress else {
            throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(
                occurrenceID: occurrence.id
            )
        }
    }

    private func activeDuration(of sessionState: SessionState, at now: Date) throws -> TimeInterval {
        let session = sessionState.session
        guard session.accumulatedActiveSeconds >= 0 else {
            throw TaskProgressServiceError.negativeAccumulatedDuration(sessionID: session.id)
        }

        switch sessionState.state {
        case .running:
            return session.accumulatedActiveSeconds + (try runningSegmentDuration(session, at: now))
        case .paused:
            guard now >= session.startedAt else {
                throw TaskProgressServiceError.timeBeforeSessionStart(sessionID: session.id)
            }
            return session.accumulatedActiveSeconds
        case .ended:
            if let endedAt = session.endedAt, now < endedAt {
                throw TaskProgressServiceError.timeBeforeSessionEnd(sessionID: session.id)
            }
            return session.accumulatedActiveSeconds
        }
    }

    private func runningSegmentDuration(_ session: TimerSession, at now: Date) throws -> TimeInterval {
        guard now >= session.lastResumedAt else {
            throw TaskProgressServiceError.timeBeforeLastResume(sessionID: session.id)
        }
        return now.timeIntervalSince(session.lastResumedAt)
    }
}
