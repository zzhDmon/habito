import Foundation

/// 任务实例来自模板展开，还是家长对某一天的独立覆盖。
nonisolated enum TaskOccurrenceOrigin: Equatable, Sendable {
    /// 由模板生成；版本号用于后续判断尚未开始的实例是否需要更新。
    case generated(templateRevision: Int)

    /// 当天单独修改、恢复或新增；后续模板编辑不得覆盖它。
    case detachedOverride

    /// 只有模板生成的实例才参与模板修订同步。
    var receivesTemplateUpdates: Bool {
        switch self {
        case .generated:
            true
        case .detachedOverride:
            false
        }
    }
}
