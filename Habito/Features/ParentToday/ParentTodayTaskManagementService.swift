import Foundation
import SwiftData

/// 集中执行家长对单日任务实例的修改，避免 View 直接编排 SwiftData 事务。
@MainActor
struct ParentTodayTaskManagementService {
    private let context: ModelContext
    private var calendar: Calendar
    private let timeZone: TimeZone
    private let completionService: TaskCompletionService

    init(
        context: ModelContext, calendar: Calendar, timeZone: TimeZone,
        completionService: TaskCompletionService? = nil
    ) {
        self.context = context
        self.calendar = calendar
        self.timeZone = timeZone
        self.completionService = completionService ?? TaskCompletionService(context: context)
        self.calendar.timeZone = timeZone
    }

    /// 只调整当前实例的计划时间，并把实例标记为脱离模板的单日覆盖。
    func reschedule(occurrenceID: UUID, to scheduledAt: Date, at now: Date) throws {
        let occurrence = try occurrence(id: occurrenceID)
        let status = try validatedStatus(of: occurrence)
        guard status == .pending || status == .skipped else {
            throw ParentTodayTaskManagementError.actionUnavailable(
                occurrenceID: occurrenceID,
                status: status
            )
        }
        let occurrenceDate = try validatedDate(of: occurrence)
        let newDate = try LocalDate(date: scheduledAt, calendar: calendar, timeZone: timeZone)
        guard newDate == occurrenceDate else {
            throw ParentTodayTaskManagementError.scheduledTimeOutsideOccurrenceDate(
                occurrenceID: occurrenceID
            )
        }

        occurrence.scheduledAt = scheduledAt
        occurrence.isDetachedOverride = true
        occurrence.updatedAt = now
        try context.save()
    }

    /// 跳过一个尚未开始的实例。
    func skip(occurrenceID: UUID, at now: Date) throws {
        try apply(.skip, to: occurrenceID, at: now)
    }

    /// 恢复一个已跳过的实例。
    func restore(occurrenceID: UUID, at now: Date) throws {
        try apply(.restore, to: occurrenceID, at: now)
    }

    /// 由家长把待处理或已跳过实例更正为完成，不伪造计时时长。
    ///
    /// 已跳过实例的恢复由完成用例拥有原子保存边界，不在本服务先改状态。
    func correctAsCompleted(occurrenceID: UUID, at now: Date) throws {
        let occurrence = try occurrence(id: occurrenceID)
        let status = try validatedStatus(of: occurrence)
        if status == .inProgress {
            throw ParentTodayTaskManagementError.inProgressCannotBeCorrected(
                occurrenceID: occurrenceID
            )
        }
        guard status == .pending || status == .skipped else {
            throw ParentTodayTaskManagementError.actionUnavailable(
                occurrenceID: occurrenceID,
                status: status
            )
        }

        _ = try completionService.correctAsCompleted(occurrence, at: now)
    }

    private func apply(
        _ action: TaskOccurrenceAction,
        to occurrenceID: UUID,
        at now: Date
    ) throws {
        let occurrence = try occurrence(id: occurrenceID)
        let status = try validatedStatus(of: occurrence)
        occurrence.statusRawValue = try status.applying(action).rawValue
        occurrence.updatedAt = now
        try context.save()
    }

    private func occurrence(id: UUID) throws -> TaskOccurrence {
        let descriptor = FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == id })
        guard let occurrence = try context.fetch(descriptor).first else {
            throw ParentTodayTaskManagementError.occurrenceNotFound(occurrenceID: id)
        }
        return occurrence
    }

    private func validatedDate(of occurrence: TaskOccurrence) throws -> LocalDate {
        do {
            return try LocalDate(dateKey: occurrence.dateKey)
        } catch {
            throw ParentTodayTaskManagementError.invalidOccurrenceDate(
                occurrenceID: occurrence.id,
                value: occurrence.dateKey
            )
        }
    }

    private func validatedStatus(of occurrence: TaskOccurrence) throws -> TaskOccurrenceStatus {
        guard let status = occurrence.status else {
            throw ParentTodayTaskManagementError.invalidOccurrenceStatus(
                occurrenceID: occurrence.id,
                value: occurrence.statusRawValue
            )
        }
        return status
    }
}
