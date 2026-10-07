/// 页面载入与未配置分离，避免读失败被当空白新建覆盖旧资料。
nonisolated enum FamilyProfileEditorLoadState: Equatable, Sendable {
    case idle
    case ready
    case failed
}
