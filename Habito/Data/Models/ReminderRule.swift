import Foundation
import SwiftData

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

    var taskTemplate: TaskTemplate?

    init(
        id: UUID = UUID(),
        taskTemplateID: UUID,
        recurrence: TaskRecurrence,
        timeOfDayMinutes: Int,
        isEnabled: Bool = true
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
    }

    /// 无法识别的原始值返回 `nil`，让数据迁移或诊断层明确处理，而不是静默猜测。
    var scheduleType: TaskRecurrenceKind? {
        TaskRecurrenceKind(rawValue: scheduleTypeRawValue)
    }

    /// 从稳定位掩码还原星期集合。
    var weekdays: Set<Weekday> {
        Set(Weekday.allCases.filter { weekdayMask & (1 << $0.rawValue) != 0 })
    }
}
