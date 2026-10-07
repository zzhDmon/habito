import SwiftData

/// 在主 actor 同一上下文加载或原子保存双名字，不操作PIN、奖励、通知或宠物数值。
///
/// 没有资料行才表示未设置；损坏和部分资料不得静默显示成空态或由新输入覆盖修复。
@MainActor
struct FamilyProfileService {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    /// 从组合根注入主写上下文和同步保存边界，便于测试保存失败。
    ///
    /// - Important: 回调必须成功提交一次或抛错，不可先提交成功再抛错；服务只回滚自身干净事务。
    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.saveChanges = saveChanges
    }

    /// 只读完整有效资料；查询不会为旧家庭创建假名字。
    ///
    /// - Returns: 两资料均不存在时返回nil，均有效时返回不可变名字。
    /// - Throws: 未保存编辑、半档案/错误身份/重复资料、非法存储名字或系统读取失败。
    func load() throws -> FamilyProfileNames? {
        try requireCleanContext()
        return try storedProfiles().map { try validatedStoredNames(child: $0.child, pet: $0.pet) }
    }

    /// 把两字段作为一个配置提交；相同字节输入幂等，不依赖unique碰撞的隐式upsert。
    ///
    /// - Parameter names: 已经过纯校验的用户输入，不代填或截断。
    /// - Returns: 本次是否创建或更新了资料；同值重试为false且不再次保存。
    /// - Throws: 脏上下文、损坏存储、系统读取或保存错误；失败恢复两个旧字段并保留原错误。
    @discardableResult
    func save(_ names: FamilyProfileNames) throws -> Bool {
        try requireCleanContext()
        let stored = try storedProfiles()
        let original = try stored.map { try validatedStoredNames(child: $0.child, pet: $0.pet) }
        if let original, sameBytes(original, names) { return false }

        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        let child = stored?.child ?? ChildProfile(names: names)
        let pet = stored?.pet ?? Pet(names: names)
        if stored != nil {
            child.update(names: names)
            pet.update(names: names)
        } else {
            context.insert(child)
            context.insert(pet)
        }
        do {
            try saveChanges(context)
            return true
        } catch {
            // 17的活跃对象可能保留标量缓存；先恢复两个旧字段，再撤回本用例事务。
            // 开始前已拒绝脏上下文，rollback不会丢弃别的页面编辑，也不做补偿保存。
            if let original {
                child.update(names: original)
                pet.update(names: original)
            }
            context.rollback()
            throw error
        }
    }

    private func requireCleanContext() throws {
        guard !context.hasChanges else { throw FamilyProfileServiceError.pendingContextChanges }
    }

    private func storedProfiles() throws -> (child: ChildProfile, pet: Pet)? {
        let children = try context.fetch(FetchDescriptor<ChildProfile>())
        let pets = try context.fetch(FetchDescriptor<Pet>())
        if children.isEmpty && pets.isEmpty { return nil }
        guard children.count == 1, pets.count == 1, let child = children.first, let pet = pets.first,
            child.singletonKey == ChildProfile.defaultKey, pet.singletonKey == Pet.defaultKey
        else { throw FamilyProfileServiceError.inconsistentStoredProfiles }
        return (child, pet)
    }

    private func validatedStoredNames(child: ChildProfile, pet: Pet) throws -> FamilyProfileNames {
        let names: FamilyProfileNames
        do {
            names = try FamilyProfileNames(childNickname: child.nickname, petName: pet.name)
        } catch {
            throw FamilyProfileServiceError.invalidStoredNames
        }
        // 校验器会清理输入两端，但读取不能悄悄修库或掩盖旧存储不一致。
        guard child.nickname.utf8.elementsEqual(names.childNickname.utf8),
            pet.name.utf8.elementsEqual(names.petName.utf8)
        else { throw FamilyProfileServiceError.invalidStoredNames }
        return names
    }

    private func sameBytes(_ lhs: FamilyProfileNames, _ rhs: FamilyProfileNames) -> Bool {
        lhs.childNickname.utf8.elementsEqual(rhs.childNickname.utf8)
            && lhs.petName.utf8.elementsEqual(rhs.petName.utf8)
    }
}
