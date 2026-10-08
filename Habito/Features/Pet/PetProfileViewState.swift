/// 宠物资料的只读状态；没有资料与读取失败必须分开，不能为旧家庭创造默认名字。
nonisolated enum PetProfileViewState: Equatable, Sendable {
    case loading
    case notConfigured
    case loaded(FamilyProfileNames)
    case failed
}
