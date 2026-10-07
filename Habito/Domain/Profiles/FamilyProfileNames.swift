import Foundation

/// 单孩子、单只小狗的有效名字；只表达输入事实，不代表账户或宠物数值已经初始化。
///
/// 不可变值可跨 actor 传递，校验不读取设备状态或持久化。界面草稿应保留在调用方，
/// 只有两字段都有效才构造此值，避免把部分输入误当作已保存的家庭配置。
nonisolated struct FamilyProfileNames: Equatable, Sendable {
    let childNickname: String
    let petName: String

    /// 校验名字并去除两端空白；不截断或代填用户输入。
    ///
    /// - Parameters:
    ///   - childNickname: 孩子的昵称，允许 Unicode 和内部空格。
    ///   - petName: 小狗的名字，遵循相同的单行校验规则。
    /// - Throws: `FamilyProfileNameError` 指明为空或含内部换行的字段；两者都无效时优先孩子字段。
    /// - Important: 错误不携带原始名字；调用方也不得将名字写入诊断日志。
    /// - Note: 单行和两端清理是当前任务卡明确记录的验证假设；尚未规定最大长度。
    init(childNickname: String, petName: String) throws {
        self.childNickname = try Self.validatedName(
            childNickname,
            emptyError: .emptyChildNickname,
            lineBreakError: .lineBreakInChildNickname
        )
        self.petName = try Self.validatedName(
            petName,
            emptyError: .emptyPetName,
            lineBreakError: .lineBreakInPetName
        )
    }

    private static func validatedName(
        _ input: String,
        emptyError: FamilyProfileNameError,
        lineBreakError: FamilyProfileNameError
    ) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw emptyError }

        // 不只检查 ASCII 的换行符：粘贴的 Unicode 行/段分隔符也不能进入单行名字。
        guard !name.unicodeScalars.contains(where: CharacterSet.newlines.contains) else {
            throw lineBreakError
        }
        return name
    }
}
