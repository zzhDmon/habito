/// 模板保存结果；通知权限失败不会回滚已成功写入的任务。
enum TaskTemplateSaveOutcome: Equatable {
    case failed
    case saved
    case savedWithNotificationWarning
}
