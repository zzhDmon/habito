import Foundation

/// 完成相对本次提交提醒快照的时间类型；旧历史缺证据，不能回算成自主。
nonisolated enum CompletionTiming: String, CaseIterable, Sendable {
    case beforeReminder
    case afterReminder
    case unknown

    /// 以关联提交的时间判定自主性，家长通过时间与系统送达都不是输入。
    ///
    /// - Parameters:
    ///   - submittedAt: 本次最终有效提交的绝对时刻。
    ///   - reminderAt: 此提交冻结的提醒绝对时刻。
    /// - Returns: 严格早于为 beforeReminder，相等或晚于为 afterReminder。
    static func classify(submittedAt: Date, reminderAt: Date) -> Self {
        submittedAt < reminderAt ? .beforeReminder : .afterReminder
    }
}
