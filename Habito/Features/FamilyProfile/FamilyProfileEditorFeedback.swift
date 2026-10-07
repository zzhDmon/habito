/// 名字校验/保存反馈，不含原始输入，也不把保存成功解释成宠物奖励。
nonisolated enum FamilyProfileEditorFeedback: Equatable, Sendable {
    case validation(FamilyProfileNameError)
    case storageFailure
    case saved
}
