import Foundation
import SwiftData

/// 一次只运行一项：预检不写库，确认后暂停其他会话与启动目标共享一次保存。
@MainActor
struct TaskTimingSwitchService {
    private let context: ModelContext
    private let query: TodayTaskQueryService
    private let saveChanges: (ModelContext) throws -> Void

    /// 保存边界仅供失败测试替换；时钟由每次操作显式注入，不依赖后台定时器。
    init(
        context: ModelContext, calendar: Calendar, timeZone: TimeZone,
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        query = TodayTaskQueryService(context: context, calendar: calendar, timeZone: timeZone)
        self.saveChanges = saveChanges
    }

    /// 查出包括跨午夜在内的其他运行任务；存量多个运行任务要全部列入确认。
    /// - Throws: 未保存上下文、非法时间、损坏会话或不可计时目标显式失败。
    func plan(for targetID: UUID, at now: Date) throws -> TaskTimingSwitchPlan {
        guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw RewardLedgerError.invalidTimestamp }
        let target = try query.item(id: targetID, at: now)
        guard !target.isAwaitingReview,
            target.status == .pending || (target.status == .inProgress && target.activeSessionState != nil)
        else { throw TaskTimingSwitchError.targetUnavailable }
        let sessions = try context.fetch(FetchDescriptor<TimerSession>())
        var runningIDs = Set<UUID>()
        for session in sessions {
            guard let state = session.state else {
                throw TaskProgressServiceError.invalidSessionState(
                    sessionID: session.id, rawValue: session.stateRawValue)
            }
            if state == .running && session.occurrenceID != targetID { runningIDs.insert(session.occurrenceID) }
        }
        let running = try runningIDs.map { try query.item(id: $0, at: now) }.sorted {
            ($0.scheduledAt, $0.id.uuidString) < ($1.scheduledAt, $1.id.uuidString)
        }
        return TaskTimingSwitchPlan(target: target, runningTasks: running)
    }

    /// 再次核对确认的任务集合；确认期间事实变化时不能顺带暂停用户没看见的新任务。
    /// - Parameters:
    ///   - targetID: 要开始或继续的任务。
    ///   - now: 同一次切换所有计时段的边界时刻。
    ///   - confirmedRunningIDs: 用户明确同意暂停的集合；空集合表示普通开始。
    /// - Returns: 已保存的目标活动会话；重复意图返回同一会话且不重置计时。
    /// - Throws: 验证或保存失败；已暂存的暂停/启动一起恢复，拒绝回滚其他未保存草稿。
    func start(for targetID: UUID, at now: Date, confirmedRunningIDs: Set<UUID> = []) throws -> TimerSession {
        let latest = try plan(for: targetID, at: now)
        // 成功后的重复确认只读命中已运行目标，不能再创建第二段或重置起点。
        let progress = TaskProgressService(context: context, saveTimingChanges: { _ in })
        let target = try occurrence(targetID)
        if latest.target.activeSessionState == .running && latest.runningTasks.isEmpty {
            return try progress.startTiming(for: target, at: now)
        }
        guard latest.runningIDs == confirmedRunningIDs else {
            throw confirmedRunningIDs.isEmpty ? TaskTimingSwitchError.confirmationRequired : .runningTasksChanged
        }
        let others = try latest.runningTasks.map { try occurrence($0.id) }
        let originals = ([target] + others).map { ($0, $0.statusRawValue, $0.updatedAt) }
        let touchedIDs = Set(originals.map { $0.0.id })
        let sessions = try context.fetch(FetchDescriptor<TimerSession>()).filter {
            touchedIDs.contains($0.occurrenceID)
        }
        let originalSessions = sessions.map { ($0, $0.stateRawValue, $0.lastResumedAt, $0.accumulatedActiveSeconds) }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        var insertedSession: TimerSession?
        do {
            for other in others { _ = try progress.pauseTiming(for: other, at: now) }
            let active: TimerSession
            if latest.target.status == .pending {
                active = try progress.startTiming(for: target, at: now)
                insertedSession = active
            } else {
                active = try progress.resumeTiming(for: target, at: now)
            }
            try saveChanges(context)
            return active
        } catch {
            // 17系回滚新双向关系可能递归恢复；先拆本事务新增关系，旧事实不删除不补偿保存。
            if let insertedSession {
                insertedSession.occurrence = nil
                target.timerSessions.removeAll { $0.id == insertedSession.id }
            }
            for (occurrence, status, updatedAt) in originals {
                occurrence.statusRawValue = status
                occurrence.updatedAt = updatedAt
            }
            // 旧runtime的标量缓存不总跟随rollback同步，先恢复本事务改动的字段。
            for (session, state, resumedAt, accumulated) in originalSessions {
                session.stateRawValue = state
                session.lastResumedAt = resumedAt
                session.accumulatedActiveSeconds = accumulated
            }
            context.rollback()
            throw error
        }
    }

    private func occurrence(_ id: UUID) throws -> TaskOccurrence {
        let values = try context.fetch(FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == id }))
        guard let value = values.first else { throw TodayTaskQueryError.occurrenceNotFound(occurrenceID: id) }
        return value
    }
}
