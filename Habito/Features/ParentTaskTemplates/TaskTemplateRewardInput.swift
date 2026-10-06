import Foundation

/// 保留家长尚未校验的原始输入，避免数字绑定在解析失败时静默沿用旧金额。
///
/// SwiftUI 的数字键盘只提供输入提示，粘贴和硬件键盘仍能输入任意文本。
/// 因此在调用保存用例前一次性解析所有字段；失败时原文仍保留，便于纠正。
struct TaskTemplateRewardInput: Equatable, Sendable {
    var xp: String
    var baseCoins: String
    var autonomyCoins: String

    init(draft: TaskTemplateDraft) {
        xp = String(draft.xpReward)
        baseCoins = String(draft.coinReward)
        autonomyCoins = String(draft.activeBonusCoin)
    }

    /// 将完整、可表示的非负整数写入草稿；总金币溢出仍由保存服务统一校验。
    /// - Throws: 空值、非 ASCII 整数或超出 `Int` 范围时抛出输入错误。
    func applying(to draft: TaskTemplateDraft) throws -> TaskTemplateDraft {
        var result = draft
        result.xpReward = try amount(xp)
        result.coinReward = try amount(baseCoins)
        result.activeBonusCoin = try amount(autonomyCoins)
        return result
    }

    private func amount(_ rawValue: String) throws -> Int {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
            value.utf8.allSatisfy({ (48...57).contains($0) }),
            let amount = Int(value)
        else { throw TaskTemplateEditorError.invalidRewardInput }
        return amount
    }
}
