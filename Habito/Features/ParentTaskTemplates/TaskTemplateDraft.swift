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
