import Foundation
import SwiftData

/// 集中管理任务实例的计时会话与完成记录事务。
///
/// 服务运行在主 actor，保证 SwiftData 模型不会跨并发域共享。调用方必须注入每次
/// 操作的绝对时间；前后台恢复只需重新计算时间差，不依赖后台持续运行计时器。
@MainActor
struct TaskProgressService {
    private let context: ModelContext
    private let saveTimingChanges: (ModelContext) throws -> Void

    /// 单项操作默认立即保存；跨任务用例注入暂存边界后负责一次保存与失败回滚。
    /// - Important: 暂存闭包只能用于拥有完整事务边界的用例，不能从View直接注入。
    init(context: ModelContext, saveTimingChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveTimingChanges = saveTimingChanges
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
        context.insert(session)
        session.occurrence = occurrence
        occurrence.statusRawValue = nextStatus.rawValue
        occurrence.updatedAt = now
        try saveTimingChanges(context)
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
        try saveTimingChanges(context)
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
        try saveTimingChanges(context)
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

    /// 兼容 V0 夹具的无结算完成入口；正式 App 使用 TaskCompletionService。
    ///
    /// - Important: 不发奖，仅用于旧历史/迁移测试，不能与新奖励撤销入口混用。
    func complete(
        _ occurrence: TaskOccurrence,
        at now: Date,
        source: CompletionSource
    ) throws -> CompletionRecord {
        let wasCompleted = occurrence.status == .completed
        let record = try stageCompletion(occurrence, at: now, source: source)
        if !wasCompleted { try context.save() }
        return record
    }

    /// 暂存完成和计时终态，让新结算用例与两种资产共享一次保存。
    ///
    /// - Important: 不自行保存；调用方必须拥有自动保存关闭与失败回滚边界。
    ///   不传 rewardSnapshot 仍走旧零/未知写路径，仅供旧历史兼容测试。
    func stageCompletion(
        _ occurrence: TaskOccurrence,
        at now: Date,
        source: CompletionSource,
        rewardSnapshot: CompletionRewardSnapshot? = nil
    ) throws -> CompletionRecord {
        guard source != .parentApproval else { throw TaskCompletionServiceError.invalidConfiguration(occurrence.id) }
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
        if let rewardSnapshot, rewardSnapshot.submittedAt != now {
            throw TaskCompletionServiceError.submissionTimeMismatch(occurrence.id)
        }
        let nextStatus = try status.applying(.complete)
        let totalDuration = try sessions.reduce(0) { partial, sessionState in
            partial + (try activeDuration(of: sessionState, at: now))
        }
        guard totalDuration.isFinite, totalDuration >= 0 else {
            throw TaskCompletionServiceError.invalidDuration(occurrence.id)
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
            updatedAt: now,
            completionTiming: rewardSnapshot?.timing ?? .unknown,
            reminderAtSnapshot: rewardSnapshot?.reminderAt,
            xpRewardSnapshot: rewardSnapshot?.xp ?? 0,
            coinRewardSnapshot: rewardSnapshot?.baseCoins ?? 0,
            activeBonusCoinSnapshot: rewardSnapshot?.autonomyBonusCoins ?? 0,
            settledCoinSnapshot: rewardSnapshot?.settledCoins ?? 0,
            rewardSettlementVersion: rewardSnapshot == nil ? 0 : 1
        )
        context.insert(record)
        occurrence.completionRecord = record
        occurrence.statusRawValue = nextStatus.rawValue
        occurrence.updatedAt = now
        return record
    }

    /// 提交等待时只结束计时并恢复基础 pending；等待语义来自独立提交事实，不是确认完成。
    ///
    /// - Returns: 所有计时段截至提交时刻的有效累计秒数。
    /// - Important: 仅暂存，调用方负责关闭自动保存、提交事实与一次 save/失败恢复。
    func stageSubmissionTimingEnd(_ occurrence: TaskOccurrence, at now: Date) throws -> TimeInterval {
        let status = try validatedStatus(of: occurrence)
        guard status == .pending || status == .inProgress, try completionRecord(for: occurrence) == nil else {
            throw TaskSubmissionError.unavailableState(occurrence.id)
        }
        let sessions = try validatedSessions(for: occurrence)
        let active = try activeSession(in: sessions, occurrenceID: occurrence.id)
        guard status != .pending || active == nil else { throw TaskSubmissionError.corruptHistory(occurrence.id) }
        let total = try submissionDuration(of: sessions, occurrenceID: occurrence.id, at: now)
        if let active {
            active.session.accumulatedActiveSeconds = try activeDuration(of: active, at: now)
            active.session.stateRawValue = TimerSessionState.ended.rawValue
            active.session.endedAt = now
        }
        occurrence.statusRawValue = TaskOccurrenceStatus.pending.rawValue
        occurrence.updatedAt = now
        return total
    }

    /// 只读验证全部计时段，等待重试用原提交时刻校验，不能接受后来悄悄增长的时长。
    ///
    /// - Returns: 时间线合法的累计活动秒数，不改写会话。
    /// - Throws: 非有限/倒退时间、矛盾终态或无效时长，不能用正常数值掩盖坏关系。
    func submissionDuration(for occurrence: TaskOccurrence, at now: Date) throws -> TimeInterval {
        try submissionDuration(of: validatedSessions(for: occurrence), occurrenceID: occurrence.id, at: now)
    }

    private func submissionDuration(of sessions: [SessionState], occurrenceID: UUID, at now: Date) throws
        -> TimeInterval
    {
        var total: TimeInterval = 0
        for entry in sessions {
            let session = entry.session
            guard session.startedAt.timeIntervalSinceReferenceDate.isFinite,
                session.lastResumedAt.timeIntervalSinceReferenceDate.isFinite,
                session.lastResumedAt >= session.startedAt
            else { throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(occurrenceID: occurrenceID) }
            guard now >= session.lastResumedAt else {
                throw TaskProgressServiceError.timeBeforeLastResume(sessionID: session.id)
            }
            if entry.state == .ended {
                guard let endedAt = session.endedAt, endedAt.timeIntervalSinceReferenceDate.isFinite,
                    endedAt >= session.lastResumedAt, endedAt <= now
                else {
                    throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(occurrenceID: occurrenceID)
                }
            } else {
                guard session.endedAt == nil else {
                    throw TaskProgressServiceError.inconsistentOccurrenceAndSessionState(occurrenceID: occurrenceID)
                }
            }
            total += try activeDuration(of: entry, at: now)
        }
        guard total.isFinite, total >= 0 else { throw TaskCompletionServiceError.invalidDuration(occurrenceID) }
        return total
    }

    /// 兼容 V0 的删除式撤销，仅限旧夹具；正式 App 使用审计撤销服务。
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
        // 新结算必须走审计冲正，旧删除入口不能删掉已有奖励对应的完成事实。
        guard record.rewardSettlementVersion == 0 else {
            throw TaskCompletionServiceError.legacyUndoCannotDeleteSettlement(record.id)
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
        try TaskSubmissionHistory(context: context).requireNotWaiting(occurrence.id)
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

    /// 只取当前未撤销事实；撤销历史保持但不作为下一次完成的幂等命中。
    func completionRecord(for occurrence: TaskOccurrence) throws -> CompletionRecord? {
        let occurrenceID = occurrence.id
        let descriptor = FetchDescriptor<CompletionRecord>(
            predicate: #Predicate { $0.occurrenceID == occurrenceID && $0.revokedAt == nil }
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
