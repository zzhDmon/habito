import SwiftData

// 冻结自ac9b505的8.0.0；名字、字段和关系不能跟随当前模型演进。
extension HabitoSchemaV7 {
    /// 本地单孩子的真实昵称；没有记录表示尚未设置，不从示例或PIN状态推断名字。
    ///
    /// `@Model` 仅承担持久化映射，实例生命周期由主 actor 的 ModelContext 管理。
    /// 唯一业务键防止单家庭产生多个档案，但不能代替后续写用例的事务与幂等检查。
    @Model
    final class ChildProfile {
        static let defaultKey = "habito.child"

        @Attribute(.unique) private(set) var singletonKey: String
        private(set) var nickname: String

        /// 构造未保存档案，只接受两个名字均有效的纯值，不自动保存或初始化宠物。
        ///
        /// - Parameter names: 已校验且不代填的家庭名字；本实体只存孩子部分。
        init(names: FamilyProfileNames) {
            singletonKey = Self.defaultKey
            nickname = names.childNickname
        }

        /// 仅更新有效昵称，不改变稳定身份；由FamilyProfileService与狗名一起保存或恢复。
        func update(names: FamilyProfileNames) {
            nickname = names.childNickname
        }
    }
}
