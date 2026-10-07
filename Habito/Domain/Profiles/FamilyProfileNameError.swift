/// 名字校验的分字段错误；不含原始输入，避免错误传播时暴露孩子资料。
nonisolated enum FamilyProfileNameError: Error, Equatable, Sendable {
    case emptyChildNickname
    case emptyPetName
    case lineBreakInChildNickname
    case lineBreakInPetName
}
