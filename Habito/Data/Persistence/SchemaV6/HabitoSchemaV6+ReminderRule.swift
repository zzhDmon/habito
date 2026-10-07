import Foundation
import SwiftData

// 冻结自 8e98ca7 的结构 7.0.0；历史字段、默认与关系不能随活跃模型演进。
extension HabitoSchemaV6 {
    /// 任务模板的一次性或按星期提醒规则。
    ///
    /// 星期集合保存为位掩码而不是可变数组，确保值稳定、易迁移，并避免 SwiftData
    /// 将数组作为不可查询的外部变换属性。第 N 位对应 `Weekday.rawValue == N`。
    @Model
    final class ReminderRule {
        @Attribute(.unique) private(set) var id: UUID
        @Attribute(.unique) private(set) var taskTemplateID: UUID
        var scheduleTypeRawValue: String
        var timeOfDayMinutes: Int
        var weekdayMask: Int
        var oneOffDateKey: String?
        var startDateKey: String
        var endDateKey: String?
        var isEnabled: Bool
        /// 计划与截止可空；原 timeOfDayMinutes 仍是提醒，新增属性不重新解释旧时刻。
        var plannedTimeOfDayMinutes: Int?
        var deadlineTimeOfDayMinutes: Int?

        var taskTemplate: TaskTemplate?

        init(
            id: UUID = UUID(),
            taskTemplateID: UUID,
            recurrence: TaskRecurrence,
            timeOfDayMinutes: Int,
            isEnabled: Bool = true,
            plannedTimeOfDayMinutes: Int? = nil,
            deadlineTimeOfDayMinutes: Int? = nil
        ) {
            self.id = id
            self.taskTemplateID = taskTemplateID
            self.scheduleTypeRawValue = recurrence.kind.rawValue
            self.timeOfDayMinutes = timeOfDayMinutes
            self.weekdayMask = recurrence.weekdays.reduce(into: 0) { mask, weekday in
                mask |= 1 << weekday.rawValue
            }
            self.oneOffDateKey = recurrence.oneOffDate?.dateKey
            self.startDateKey = recurrence.startDate.dateKey
            self.endDateKey = recurrence.endDate?.dateKey
            self.isEnabled = isEnabled
            self.plannedTimeOfDayMinutes = plannedTimeOfDayMinutes
            self.deadlineTimeOfDayMinutes = deadlineTimeOfDayMinutes
        }

        /// 无法识别的原始值返回 `nil`，让数据迁移或诊断层明确处理，而不是静默猜测。
        var scheduleType: TaskRecurrenceKind? {
            TaskRecurrenceKind(rawValue: scheduleTypeRawValue)
        }

        /// 从稳定位掩码还原星期集合。
        var weekdays: Set<Weekday> {
            Set(Weekday.allCases.filter { weekdayMask & (1 << $0.rawValue) != 0 })
        }

        /// 将持久化标量安全还原为经过领域校验的重复规则。
        ///
        /// - Returns: 可直接交给 `TaskRecurrenceExpander` 的规则。
        /// - Throws: 原始类型、日期键或字段组合损坏时抛出 `ReminderRuleDecodingError`。
        func decodedRecurrence() throws -> TaskRecurrence {
            guard let scheduleType else {
                throw ReminderRuleDecodingError.unknownScheduleType(scheduleTypeRawValue)
            }
            let startDate = try decodeDateKey(startDateKey, field: "startDateKey")
            let endDate = try endDateKey.map { try decodeDateKey($0, field: "endDateKey") }

            switch scheduleType {
            case .once:
                guard let oneOffDateKey else {
                    throw ReminderRuleDecodingError.missingDateKey(field: "oneOffDateKey")
                }
                let oneOffDate = try decodeDateKey(oneOffDateKey, field: "oneOffDateKey")
                guard startDate == oneOffDate, endDate == oneOffDate else {
                    throw ReminderRuleDecodingError.inconsistentOnceRange
                }
                return .once(on: oneOffDate)

            case .weekly:
                guard oneOffDateKey == nil else {
                    throw ReminderRuleDecodingError.unexpectedOneOffDateForWeekly
                }
                do {
                    return try .weekly(on: weekdays, starting: startDate, ending: endDate)
                } catch let error as TaskRecurrenceError {
                    throw ReminderRuleDecodingError.invalidRecurrence(error)
                }
            }
        }

        /// 用已经过领域校验的规则更新持久化标量，避免编辑服务重复位掩码编码逻辑。
        func update(
            recurrence: TaskRecurrence,
            timeOfDayMinutes: Int,
            isEnabled: Bool
        ) {
            scheduleTypeRawValue = recurrence.kind.rawValue
            self.timeOfDayMinutes = timeOfDayMinutes
            weekdayMask = recurrence.weekdays.reduce(into: 0) { mask, weekday in
                mask |= 1 << weekday.rawValue
            }
            oneOffDateKey = recurrence.oneOffDate?.dateKey
            startDateKey = recurrence.startDate.dateKey
            endDateKey = recurrence.endDate?.dateKey
            self.isEnabled = isEnabled
        }

        private func decodeDateKey(_ value: String, field: String) throws -> LocalDate {
            do {
                return try LocalDate(dateKey: value)
            } catch {
                throw ReminderRuleDecodingError.invalidDateKey(field: field, value: value)
            }
        }
    }
}
