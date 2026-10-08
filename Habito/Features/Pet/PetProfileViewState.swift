/// 宠物真实资料与成长快照状态；没有资料与读取失败必须分开，不能为旧家庭创造默认名字。
nonisolated enum PetProfileViewState: Equatable, Sendable {
    case loading
    case notConfigured
    case loaded(PetCareSnapshot)
    case failed
}
