/// 比率保留原始样本量；nil 表示没有分母，0 表示有样本但没有达成，不混为一谈。
nonisolated struct GrowthStatisticsCounts: Equatable, Sendable {
    let eligible: Int
    let completed: Int
    let autonomous: Int
    let knownTiming: Int
    let awaitingReview: Int
    let skipped: Int
    let childConfirmed: Int
    let parentApproved: Int
    let parentCorrected: Int

    /// 只接受计算器已校验的当前事实；来源仅作展示，不代替自主性判定。
    init(facts: [GrowthStatisticsFact]) {
        eligible = facts.count { $0.status != .skipped && $0.status != .cancelled }
        completed = facts.count { $0.status == .completed }
        autonomous = facts.count { $0.status == .completed && $0.completionTiming == .beforeReminder }
        knownTiming = facts.count {
            $0.status == .completed && ($0.completionTiming == .beforeReminder || $0.completionTiming == .afterReminder)
        }
        awaitingReview = facts.count { $0.isAwaitingReview }
        skipped = facts.count { $0.status == .skipped }
        childConfirmed = facts.count { $0.status == .completed && $0.completionSource == .childManual }
        parentApproved = facts.count { $0.status == .completed && $0.completionSource == .parentApproval }
        parentCorrected = facts.count { $0.status == .completed && $0.completionSource == .parentCorrection }
    }

    var completionRate: Double? { eligible == 0 ? nil : Double(completed) / Double(eligible) }
    var autonomyRate: Double? { knownTiming == 0 ? nil : Double(autonomous) / Double(knownTiming) }
    var unknownTiming: Int { completed - knownTiming }
}
