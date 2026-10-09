import Foundation

/// 新保存完成与今日全完成事实相符时的纯展示资格，不是新奖励或动画发布者。
///
/// - Important: 只能从事务返回的新结果构造，不能从页面出现或历史收据生成。
///   同一完成ID重复构造仍是相等值；后续状态持有者负责去重和失效，本类型不读写存储。
nonisolated struct TodayCompletionCelebrationEvent: Equatable, Identifiable, Sendable {
    let completionID: UUID
    let date: LocalDate
    let completedCount: Int

    var id: UUID { completionID }

    /// 只接受新孩子自行确认，且保存后的今日快照确实包含这一完成事实。
    /// - Parameters:
    ///   - completion: 保存成功后返回的收据；幂等重试的didComplete为false。
    ///   - snapshot: 同一操作后重新查询的当前今日快照，不是完成前缓存或历史日期查询。
    /// - Note: 无资格返回nil，仅不生成额外仪式；普通完成反馈和真实奖励不受影响。
    init?(completion: TaskCompletionResult, snapshot: TodayTasksSnapshot) {
        guard completion.didComplete,
            snapshot.tasks.contains(where: {
                $0.completion?.id == completion.completionID
                    && $0.completion?.source == .childManual && $0.verificationType == .selfConfirm
            })
        else { return nil }
        self.init(completionID: completion.completionID, snapshot: snapshot)
    }

    /// 新家长通过还必须匹配原提交，退回、等待、幂等旧结果和已冲正不能伪装成通关。
    /// - Parameters:
    ///   - review: 保存成功后的审核结果；不接只读历史奖励收据。
    ///   - snapshot: 审核后重新读取的当前今日快照。
    init?(review: TaskSubmissionReviewResult, snapshot: TodayTasksSnapshot) {
        guard review.didReview, review.state == .approved, !review.rewardIsRevoked,
            let completionID = review.completionID,
            snapshot.tasks.contains(where: {
                $0.completion?.id == completionID && $0.completion?.source == .parentApproval
                    && $0.verificationType == .parentApproval && $0.submission?.id == review.submissionID
                    && $0.submission?.state == .approved
            })
        else { return nil }
        self.init(completionID: completionID, snapshot: snapshot)
    }

    /// 防御矛盾的聚合值：必须核对实际有效行和稳定ID，不能只相信完成百分比。
    private init?(completionID: UUID, snapshot: TodayTasksSnapshot) {
        let tasks = snapshot.tasks.filter { $0.status != .skipped && $0.status != .cancelled }
        let completionIDs = tasks.compactMap { $0.completion?.id }
        guard snapshot.isCurrentDate, snapshot.carryOverTasks.isEmpty,
            snapshot.totalCount > 0, snapshot.completedCount == snapshot.totalCount,
            tasks.count == snapshot.totalCount, Set(tasks.map(\.id)).count == tasks.count,
            completionIDs.count == tasks.count, Set(completionIDs).count == tasks.count,
            // 原始tasks还包含被跳过行；触发ID必须属于真正计入今日结果的有效完成，不能借另一任务的数量。
            completionIDs.contains(completionID),
            tasks.allSatisfy({
                $0.date == snapshot.date && $0.status == .completed && $0.submission?.state != .waiting
            })
        else { return nil }
        self.completionID = completionID
        date = snapshot.date
        completedCount = tasks.count
    }
}
