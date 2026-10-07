/// 名字资料的读取或事务前置错误；不附原始名字，避免开发日志泄漏孩子隐私。
nonisolated enum FamilyProfileServiceError: Error, Equatable, Sendable {
    case pendingContextChanges
    case inconsistentStoredProfiles
    case invalidStoredNames
}
