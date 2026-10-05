import Foundation

/// 家长编辑器使用的可变草稿，不持有 SwiftData 模型。
struct TaskTemplateDraft: Equatable, Sendable {
    static let allowedIconNames = ["book.fill", "pencil.line", "figure.run", "music.note"]
    static let allowedColorTokens = ["task", "reading", "practice", "activity"]

    let templateID: UUID?
    var title: String
    var iconName: String
    var colorToken: String
    var timeOfDayMinutes: Int
    var targetDurationMinutes: Int
    var weekdays: Set<Weekday>
    var isEnabled: Bool
    /// 兼容值不代表家长已选择分类或产品默认奖励；编辑旧字段时也要原样保留已载入配置。
    var category: TaskCategory = .unassigned
    var timePeriod: TaskTimePeriod = .allDay
    /// 只支持两种 P0 路径；家长验收不会在孩子提交时结算奖励。
    var verificationType: TaskVerificationType = .selfConfirm
    /// 显式配置的经验，不按分类自动填奖励，也不把 0 当已确认的产品默认。
    var xpReward: Int = 0
    var coinReward: Int = 0
    /// 额外金币由提交快照的自主性决定，严格早于提醒才获得；不看系统实际送达。
    var activeBonusCoin: Int = 0

    static var new: TaskTemplateDraft {
        TaskTemplateDraft(
            templateID: nil,
            title: "",
            iconName: "book.fill",
            colorToken: "task",
            timeOfDayMinutes: 19 * 60 + 30,
            targetDurationMinutes: 15,
            weekdays: Set(Weekday.allCases),
            isEnabled: true
        )
    }
}
