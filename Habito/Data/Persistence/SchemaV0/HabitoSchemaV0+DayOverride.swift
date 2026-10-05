import Foundation
import SwiftData

// 冻结自 1b5591b 的 V0 模型；迁移依赖此历史定义，不能随当前模型一起修改。
extension HabitoSchemaV0 {
    /// 家长对具体本地日期设置的上课或放假覆盖。
    @Model
    final class DayOverride {
        @Attribute(.unique) private(set) var id: UUID
        @Attribute(.unique) private(set) var dateKey: String
        var dayTypeRawValue: String
        var note: String?
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            date: LocalDate,
            dayType: DayType,
            note: String? = nil,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.dateKey = date.dateKey
            self.dayTypeRawValue = dayType.rawValue
            self.note = note
            self.updatedAt = updatedAt
        }

        var dayType: DayType? {
            DayType(rawValue: dayTypeRawValue)
        }
    }
}
