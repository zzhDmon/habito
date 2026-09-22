import Foundation

/// 已通过领域校验的一次性或按星期重复规则。
///
/// 属性保持统一形状，方便 M1-002 映射到 SwiftData；调用方只能通过工厂方法
/// 创建实例，因此不会出现一次性规则带星期、或每周规则星期为空的组合。
nonisolated struct TaskRecurrence: Equatable, Sendable {
    let kind: TaskRecurrenceKind
    let weekdays: Set<Weekday>
    let oneOffDate: LocalDate?
    let startDate: LocalDate
    let endDate: LocalDate?

    private init(
        kind: TaskRecurrenceKind,
        weekdays: Set<Weekday>,
        oneOffDate: LocalDate?,
        startDate: LocalDate,
        endDate: LocalDate?
    ) {
        self.kind = kind
        self.weekdays = weekdays
        self.oneOffDate = oneOffDate
        self.startDate = startDate
        self.endDate = endDate
    }

    /// 创建只在指定日期发生一次的规则。
    static func once(on date: LocalDate) -> TaskRecurrence {
        TaskRecurrence(
            kind: .once,
            weekdays: [],
            oneOffDate: date,
            startDate: date,
            endDate: date
        )
    }

    /// 创建按星期重复的规则。
    ///
    /// - Parameters:
    ///   - weekdays: 至少一个星期值。
    ///   - startDate: 规则生效的第一天。
    ///   - endDate: 可选的最后生效日；传入时不得早于 `startDate`。
    /// - Returns: 通过星期集合与日期范围校验的每周重复规则。
    /// - Throws: 星期集合为空或日期范围倒置时抛出 `TaskRecurrenceError`。
    static func weekly(
        on weekdays: Set<Weekday>,
        starting startDate: LocalDate,
        ending endDate: LocalDate? = nil
    ) throws -> TaskRecurrence {
        guard !weekdays.isEmpty else {
            throw TaskRecurrenceError.emptyWeekdays
        }
        if let endDate, endDate < startDate {
            throw TaskRecurrenceError.endDateBeforeStartDate
        }

        return TaskRecurrence(
            kind: .weekly,
            weekdays: weekdays,
            oneOffDate: nil,
            startDate: startDate,
            endDate: endDate
        )
    }
}
