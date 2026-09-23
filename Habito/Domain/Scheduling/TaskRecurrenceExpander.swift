import Foundation

/// 将一次性或按星期重复规则展开为确定的任务候选。
///
/// 展开器只做日期计算，不读取系统当前时间，也不执行持久化。显式注入 `Calendar`
/// 和 `TimeZone` 后，同一组输入可在测试、模拟器与真机上得到相同结果。
nonisolated struct TaskRecurrenceExpander: Sendable {
    private let calendar: Calendar
    private let timeZone: TimeZone

    /// 创建规则展开器。
    ///
    /// - Parameters:
    ///   - calendar: 业务使用的日历；V0 组合根应注入公历。
    ///   - timeZone: 用于解释任务本地日期与分钟数的业务时区。
    init(calendar: Calendar, timeZone: TimeZone) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
    }

    /// 在请求范围内展开任务候选，首尾日期均包含在内。
    ///
    /// 请求范围会与规则自身的开始、结束日期取交集。对于夏令时切换日中不存在的
    /// 本地时刻，系统会顺延到当天第一个能保留分钟语义的时刻（例如 02:30 → 03:30）；
    /// 对于出现两次的本地时刻，固定选择第一次。
    ///
    /// - Parameters:
    ///   - recurrence: 已由 `TaskRecurrence` 工厂校验的重复规则。
    ///   - timeOfDayMinutes: 从本地午夜起计算的分钟数，合法范围为 0...1439。
    ///   - requestedStart: 调用方需要生成的第一天。
    ///   - requestedEnd: 调用方需要生成的最后一天。
    /// - Returns: 按本地日期升序排列的候选；无交集时返回空数组。
    /// - Throws: 输入范围错误，或注入的日历无法完成日期/时刻转换时抛出
    ///   `TaskRecurrenceExpansionError`。
    func expand(
        _ recurrence: TaskRecurrence,
        timeOfDayMinutes: Int,
        from requestedStart: LocalDate,
        through requestedEnd: LocalDate
    ) throws -> [ScheduledTaskCandidate] {
        guard (0..<24 * 60).contains(timeOfDayMinutes) else {
            throw TaskRecurrenceExpansionError.invalidTimeOfDayMinutes(timeOfDayMinutes)
        }
        guard requestedStart <= requestedEnd else {
            throw TaskRecurrenceExpansionError.invalidRequestedRange(
                start: requestedStart,
                end: requestedEnd
            )
        }

        let effectiveStart = max(requestedStart, recurrence.startDate)
        let effectiveEnd = min(requestedEnd, recurrence.endDate ?? requestedEnd)
        guard effectiveStart <= effectiveEnd else { return [] }

        switch recurrence.kind {
        case .once:
            guard
                let date = recurrence.oneOffDate,
                (effectiveStart...effectiveEnd).contains(date)
            else {
                return []
            }
            return [try candidate(on: date, timeOfDayMinutes: timeOfDayMinutes)]

        case .weekly:
            return try weeklyCandidates(
                recurrence,
                timeOfDayMinutes: timeOfDayMinutes,
                from: effectiveStart,
                through: effectiveEnd
            )
        }
    }

    private func weeklyCandidates(
        _ recurrence: TaskRecurrence,
        timeOfDayMinutes: Int,
        from start: LocalDate,
        through end: LocalDate
    ) throws -> [ScheduledTaskCandidate] {
        var result: [ScheduledTaskCandidate] = []
        var current = start

        while current <= end {
            let referenceDate = try referenceDate(for: current)
            let weekdayValue = calendar.component(.weekday, from: referenceDate)

            if let weekday = Weekday(rawValue: weekdayValue), recurrence.weekdays.contains(weekday) {
                result.append(try candidate(on: current, timeOfDayMinutes: timeOfDayMinutes))
            }

            guard current < end else { break }
            current = try nextDate(after: current, referenceDate: referenceDate)
        }

        return result
    }

    /// 使用正午作为日期运算锚点，避免午夜恰好处于时区规则切换区间。
    private func referenceDate(for date: LocalDate) throws -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: 12
        )

        guard let referenceDate = calendar.date(from: components) else {
            throw TaskRecurrenceExpansionError.cannotResolveDate(date)
        }

        do {
            let resolvedDate = try LocalDate(
                date: referenceDate,
                calendar: calendar,
                timeZone: timeZone
            )
            guard resolvedDate == date else {
                throw TaskRecurrenceExpansionError.cannotResolveDate(date)
            }
        } catch let error as TaskRecurrenceExpansionError {
            throw error
        } catch {
            throw TaskRecurrenceExpansionError.cannotResolveDate(date)
        }
        return referenceDate
    }

    private func nextDate(after date: LocalDate, referenceDate: Date) throws -> LocalDate {
        guard let nextReferenceDate = calendar.date(byAdding: .day, value: 1, to: referenceDate) else {
            throw TaskRecurrenceExpansionError.cannotAdvanceDate(date)
        }

        do {
            let next = try LocalDate(
                date: nextReferenceDate,
                calendar: calendar,
                timeZone: timeZone
            )
            guard next > date else {
                throw TaskRecurrenceExpansionError.cannotAdvanceDate(date)
            }
            return next
        } catch let error as TaskRecurrenceExpansionError {
            throw error
        } catch {
            throw TaskRecurrenceExpansionError.cannotAdvanceDate(date)
        }
    }

    private func candidate(
        on date: LocalDate,
        timeOfDayMinutes: Int
    ) throws -> ScheduledTaskCandidate {
        let referenceDate = try referenceDate(for: date)
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let searchStart = startOfDay.addingTimeInterval(-1)
        let hour = timeOfDayMinutes / 60
        let minute = timeOfDayMinutes % 60
        let targetComponents = DateComponents(hour: hour, minute: minute, second: 0)

        guard
            let scheduledAt = calendar.nextDate(
                after: searchStart,
                matching: targetComponents,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        else {
            throw TaskRecurrenceExpansionError.cannotResolveScheduledTime(
                date: date,
                timeOfDayMinutes: timeOfDayMinutes
            )
        }

        do {
            let resolvedDate = try LocalDate(
                date: scheduledAt,
                calendar: calendar,
                timeZone: timeZone
            )
            guard resolvedDate == date else {
                throw TaskRecurrenceExpansionError.cannotResolveScheduledTime(
                    date: date,
                    timeOfDayMinutes: timeOfDayMinutes
                )
            }
        } catch let error as TaskRecurrenceExpansionError {
            throw error
        } catch {
            throw TaskRecurrenceExpansionError.cannotResolveScheduledTime(
                date: date,
                timeOfDayMinutes: timeOfDayMinutes
            )
        }

        return ScheduledTaskCandidate(date: date, scheduledAt: scheduledAt)
    }
}
