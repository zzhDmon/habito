import SwiftData

// 冻结自ac9b505的8.0.0；名字、字段和关系不能跟随当前模型演进。
extension HabitoSchemaV7 {
    /// 本地唯一一只小狗的名字；此实体尚不代表成长、情绪或互动能力已经初始化。
    ///
    /// `@Model` 生命周期属于主 actor 的 ModelContext；没有记录表示尚未设置。
    /// 不用假Lv.1、Bond或Mood占位，避免未确认参数成为迁移事实。
    @Model
    final class Pet {
        static let defaultKey = "habito.pet"

        @Attribute(.unique) private(set) var singletonKey: String
        private(set) var name: String

        /// 构造未保存小狗，只接受有效名字；配对保存由后续同上下文用例负责。
        ///
        /// - Parameter names: 已校验的家庭名字；本实体只存小狗部分。
        init(names: FamilyProfileNames) {
            singletonKey = Self.defaultKey
            name = names.petName
        }

        /// 仅更新有效狗名；配对原子保存/失败恢复由FamilyProfileService承担，不改成长状态。
        func update(names: FamilyProfileNames) {
            name = names.petName
        }
    }
}
