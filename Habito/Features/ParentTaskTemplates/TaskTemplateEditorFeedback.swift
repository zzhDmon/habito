/// 编辑器向用户展示的校验或存储反馈。
enum TaskTemplateEditorFeedback: Equatable {
    case validation(TaskTemplateEditorError)
    case loadFailure
    case storageFailure
}
