import Foundation
import Observation

/// 主 actor 持有一次今日仪式的内存身份；不查询数据库，也不发放或确认奖励。
///
/// `@Observable` 只让界面观察当前事件，组合根负责跨页面保留同一实例。
/// - Important: 接线只能投递刚保存成功的结果；历史加载仅调用refresh。
///   去重保留到进程结束，冷启动不得把历史收据重新投递为新事务。
@MainActor
@Observable
final class TodayCompletionCelebrationViewModel {
    private(set) var event: TodayCompletionCelebrationEvent?

    @ObservationIgnored private var consumedCompletionIDs: Set<UUID> = []
    @ObservationIgnored private var claimedAnimationID: UUID?
    @ObservationIgnored private var validateEvent:
        (@MainActor (TodayTasksSnapshot) -> TodayCompletionCelebrationEvent?)?

    /// 接收新自行确认结果；返回是否生成新事件，不改变事务本身的成功语义。
    /// - Parameters:
    ///   - completion: 原事务返回值，不是从历史记录拼出的结果。
    ///   - snapshot: 该事务后重新读取的今日快照。
    /// - Returns: 只有首次新结果且符合真实全完成资格时为true。
    @discardableResult
    func receive(completion: TaskCompletionResult, snapshot: TodayTasksSnapshot) -> Bool {
        refresh(snapshot: snapshot)
        guard completion.didComplete else { return false }
        return receive(completionID: completion.completionID, snapshot: snapshot) {
            TodayCompletionCelebrationEvent(completion: completion, snapshot: $0)
        }
    }

    /// 家长通过走同一完成ID去重；等待、退回和幂等旧审核不创建新事件。
    /// - Returns: 是否生成新事件；没有资格不影响原审核反馈和已保存奖励。
    @discardableResult
    func receive(review: TaskSubmissionReviewResult, snapshot: TodayTasksSnapshot) -> Bool {
        refresh(snapshot: snapshot)
        guard review.didReview, review.state == .approved, !review.rewardIsRevoked,
            let completionID = review.completionID
        else { return false }
        return receive(completionID: completionID, snapshot: snapshot) {
            TodayCompletionCelebrationEvent(review: review, snapshot: $0)
        }
    }

    /// 只验证已有事件；撤销、跨日、待验收或数量变化时撤下，刷新绝不补播。
    /// - Note: 验证闭包只捕获原始不可变结果；不会读存储、时钟或修改账本。
    func refresh(snapshot: TodayTasksSnapshot) {
        guard let event else { return }
        guard validateEvent?(snapshot) == event else {
            invalidate()
            return
        }
    }

    /// 事实读取失败或页面无法再保证当前资格时显式撤下；保留已消费ID防止稍后重播。
    /// - Important: 调用者仍须显示其查询错误，本方法不将失败伪装成正常空态。
    func invalidate() {
        event = nil
        validateEvent = nil
        claimedAnimationID = nil
    }

    /// 关闭仅作用于按钮捕获的当前ID，陈旧按钮不能清掉随后新完成的仪式。
    func dismiss(eventID: UUID) {
        guard event?.id == eventID else { return }
        invalidate()
    }

    /// 当前事件最多领取一次动画资格，避免View重新挂载反复播放。
    /// - Returns: 首次匹配当前事件为true；静态结果始终可以直接展示。
    /// - Note: Reduce Motion界面同样消费此次资格，但不播放位移/缩放；具体呈现由UI卡实现。
    func claimAnimation(eventID: UUID) -> Bool {
        guard event?.id == eventID, claimedAnimationID != eventID else { return false }
        claimedAnimationID = eventID
        return true
    }

    private func receive(
        completionID: UUID, snapshot: TodayTasksSnapshot,
        makeEvent: @escaping @MainActor (TodayTasksSnapshot) -> TodayCompletionCelebrationEvent?
    ) -> Bool {
        // 首次尚未全完成也消费ID，否则重传较早的真收据会在后来通关时补播。
        guard consumedCompletionIDs.insert(completionID).inserted,
            let candidate = makeEvent(snapshot)
        else { return false }
        event = candidate
        validateEvent = makeEvent
        claimedAnimationID = nil
        return true
    }
}
