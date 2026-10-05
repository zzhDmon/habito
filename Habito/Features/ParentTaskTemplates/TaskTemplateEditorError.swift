import Foundation

/// 模板草稿校验、加载或保存时的明确失败原因。
enum TaskTemplateEditorError: Error, Equatable {
    case titleRequired
    case titleTooLong
    case invalidDuration
    case invalidTime
    case noWeekdays
    case unsupportedIcon
    case unsupportedColor
    case templateNotFound(UUID)
    case archivedTemplate(UUID)
    case missingRule(UUID)
    case unsupportedRecurrence(UUID)
    case invalidReward
    case rewardOverflow
    case revisionOverflow
    case invalidStoredRevision(UUID)
    case pendingContextChanges
}
