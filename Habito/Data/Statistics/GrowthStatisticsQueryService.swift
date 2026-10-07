import Foundation
import SwiftData

/// 统计读取局限在主 actor；只输出纯值，不把 SwiftData 模型传给页面或后台任务。
///
/// - Important: 不保存、回滚或补历史实例。业务日历/时区显式注入，已有审计规则统一复用。
@MainActor
struct GrowthStatisticsQueryService {
    private let context: ModelContext
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let calculator = GrowthStatisticsCalculator()
    private let taskQuery: TodayTaskQueryService

    init(context: ModelContext, calendar: Calendar, timeZone: TimeZone) {
        self.context = context
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
        taskQuery = TodayTaskQueryService(context: context, calendar: configuredCalendar, timeZone: timeZone)
    }

    /// “今天”只由调用方时刻及业务时区确定；窗口内的完成不按到账日期重新归组。
    ///
    /// - Parameters:
    ///   - period: 含今天的 7/14/30 个公历日期。
    ///   - now: 注入时钟的有限绝对时刻。
    /// - Returns: 总体、逐日和逐模板的只读统计快照。
    /// - Throws: 未保存编辑、坏实例/计时/提交/完成关系或奖励审计；底层读取错误透传。
    func snapshot(period: GrowthStatisticsPeriod, at now: Date) throws -> GrowthStatisticsSnapshot {
        guard !context.hasChanges else { throw GrowthStatisticsQueryError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw GrowthStatisticsQueryError.invalidTimestamp }
        let end = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
        let dates = try calculator.dates(endingOn: end, period: period)
        guard let start = dates.first else { throw GrowthStatisticsError.invalidWindowEnd(end) }
        let facts = try facts(from: start, through: end, at: now)
        return try calculator.snapshot(facts: facts, endingOn: end, period: period)
    }

    /// 今日概况只验证今天的实例，不让窗口外的坏历史阻断当天管理。
    ///
    /// - Parameter now: 组合根注入时钟的当前时刻。
    /// - Returns: 当日本地日期与有效完成、待验收、自主性和来源计数。
    /// - Throws: 与窗口查询相同的未保存编辑、非法时间或当日事实校验错误。
    func today(at now: Date) throws -> GrowthStatisticsDay {
        guard !context.hasChanges else { throw GrowthStatisticsQueryError.pendingContextChanges }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw GrowthStatisticsQueryError.invalidTimestamp }
        let date = try LocalDate(date: now, calendar: calendar, timeZone: timeZone)
        let facts = try facts(from: date, through: date, at: now)
        // 继续由计算器验证事实重复及矛盾；不在页面状态另造一套分母规则。
        return try calculator.day(facts: facts, on: date)
    }

    private func facts(from start: LocalDate, through end: LocalDate, at now: Date) throws -> [GrowthStatisticsFact] {
        let startKey = start.dateKey
        let endKey = end.dateKey
        let occurrences = try context.fetch(
            FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.dateKey >= startKey && $0.dateKey <= endKey }))
        return try occurrences.map { try fact(for: $0, at: now) }
    }

    private func fact(for occurrence: TaskOccurrence, at now: Date) throws -> GrowthStatisticsFact {
        guard
            occurrence.uniquenessKey
                == TaskOccurrence.makeUniquenessKey(templateID: occurrence.templateID, dateKey: occurrence.dateKey)
        else { throw GrowthStatisticsQueryError.invalidOccurrenceIdentity(occurrence.id) }
        // 复用计时/状态/提交序列校验；不能把 pending 原始值当作“未提交”的证据。
        let item = try taskQuery.item(id: occurrence.id, at: now)
        let record = try TaskProgressService(context: context).completionRecord(for: occurrence)
        let timing: CompletionTiming?
        if let completion = item.completion {
            guard let record, record.id == completion.id, record.occurrence?.id == occurrence.id,
                occurrence.completionRecord?.id == record.id
            else { throw GrowthStatisticsQueryError.invalidCompletionRelation(occurrence.id) }
            _ = try TaskCompletionAuditValidator(context: context).validate(record)
            guard record.completedAt <= now, record.rewardSettledAt.map({ $0 <= now }) ?? true else {
                throw GrowthStatisticsQueryError.completionAfterQueryTime(record.id)
            }
            timing = record.completionTiming
        } else {
            guard record == nil, occurrence.completionRecord == nil else {
                throw GrowthStatisticsQueryError.invalidCompletionRelation(occurrence.id)
            }
            timing = nil
        }
        return GrowthStatisticsFact(
            id: item.id, templateID: occurrence.templateID, date: item.date, title: item.title,
            status: item.status, isAwaitingReview: item.isAwaitingReview,
            completionTiming: timing, completionSource: item.completion?.source)
    }
}
