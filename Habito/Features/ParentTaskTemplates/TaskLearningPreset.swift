import Foundation

/// 家长主动选用的任务建议，只填未保存草稿；不创建实例或追溯改写旧奖励。
nonisolated enum TaskLearningPreset: String, CaseIterable, Sendable {
    case reading, handwriting, chineseHomework, mathHomework, english, pinyin, schoolbag, exercise, housework

    var titleKey: String { "taskPreset." + rawValue }
    var title: String {
        String(localized: String.LocalizationValue(stringLiteral: titleKey), table: "UIR1")
    }

    var durationMinutes: Int {
        switch self {
        case .reading: 15
        case .handwriting, .english, .housework: 10
        case .pinyin, .schoolbag: 5
        case .chineseHomework, .mathHomework, .exercise: 20
        }
    }

    var xp: Int { self == .reading || self == .exercise ? 10 : 5 }
    var coins: Int { self == .reading || self == .exercise ? 2 : 1 }
    var autonomyCoins: Int { self == .chineseHomework || self == .mathHomework ? 0 : 1 }
    var iconName: String {
        switch self {
        case .handwriting, .chineseHomework, .mathHomework: "pencil.line"
        case .exercise, .housework, .schoolbag: "figure.run"
        default: "book.fill"
        }
    }

    /// 点选模板明确替换名称、建议时长、分类、确认方式、奖励与重复星期。
    /// - Important: 提醒/计划/截止时刻保持家长当前输入；保存前仍可逐项修改。
    func applying(to draft: TaskTemplateDraft) -> TaskTemplateDraft {
        guard draft.templateID == nil else { return draft }
        var result = draft
        result.title = title
        result.iconName = iconName
        result.colorToken = self == .exercise ? "activity" : (iconName == "book.fill" ? "reading" : "practice")
        result.targetDurationMinutes = durationMinutes
        result.weekdays = Weekday.schoolDays
        result.category =
            self == .chineseHomework || self == .mathHomework || self == .schoolbag || self == .housework
            ? .basicResponsibility : .growth
        result.timePeriod =
            self == .chineseHomework || self == .mathHomework || self == .exercise ? .afterSchool : .evening
        result.verificationType = self == .chineseHomework || self == .mathHomework ? .parentApproval : .selfConfirm
        result.xpReward = xp
        result.coinReward = coins
        result.activeBonusCoin = autonomyCoins
        return result
    }
}
