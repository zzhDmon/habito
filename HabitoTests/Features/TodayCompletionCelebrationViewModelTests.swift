import Foundation
import Testing
@testable import Habito

/// 所有状态输入为固定快照；不依赖数据库、真实时钟、动画或等待。
@Suite("今日仪式去重与失效")
@MainActor
struct TodayCompletionCelebrationViewModelTests {
    @Test("构造和刷新全完成快照都不能从历史创建新事件")
    func initialLoadCannotCreateEvent() throws {
        let model = TodayCompletionCelebrationViewModel()
        #expect(model.event == nil)
        model.refresh(snapshot: try snapshot([task()]))
        #expect(model.event == nil)
        #expect(!model.claimAnimation(eventID: id(2)))
    }

    @Test("新确认只出现一次，重复回调不重置已领取动画")
    func duplicateCompletionPreservesSingleAnimation() throws {
        let model = TodayCompletionCelebrationViewModel()
        let current = try snapshot([task()])
        #expect(model.receive(completion: result(), snapshot: current))
        let event = try #require(model.event)
        #expect(model.claimAnimation(eventID: event.id))
        for _ in 0..<3 {
            #expect(!model.receive(completion: result(), snapshot: current))
            model.refresh(snapshot: current)
            #expect(model.event == event)
            #expect(!model.claimAnimation(eventID: event.id))
        }
    }

    @Test("幂等旧确认不是新事件，也不抢走当前仪式")
    func idempotentResultCannotCreateEvent() throws {
        let model = TodayCompletionCelebrationViewModel()
        let current = try snapshot([task()])
        #expect(!model.receive(completion: result(didComplete: false), snapshot: current))
        #expect(model.event == nil)
        #expect(model.receive(completion: result(), snapshot: current))
        #expect(!model.receive(completion: result(didComplete: false), snapshot: current))
        #expect(model.event?.id == id(2))
    }

    @Test("较早成功结果首次不全完成，稍后全完成也不能补播旧ID")
    func earlierReceiptCannotReplayWhenDayLaterFinishes() throws {
        let model = TodayCompletionCelebrationViewModel()
        let partial = try snapshot([task(), task(taskID: 3, completionID: nil, status: .pending)])
        #expect(!model.receive(completion: result(), snapshot: partial))
        let finished = try snapshot([task(), task(taskID: 3, completionID: 4)])
        model.refresh(snapshot: finished)
        #expect(model.event == nil)
        #expect(!model.receive(completion: result(), snapshot: finished))
        #expect(model.receive(completion: result(completionID: 4), snapshot: finished))
        #expect(model.event?.completedCount == 2)
    }

    @Test("关闭只清当前ID，刷新与重复投递不得恢复已关闭事件")
    func dismissedEventCannotReappear() throws {
        let model = TodayCompletionCelebrationViewModel()
        let current = try snapshot([task()])
        model.receive(completion: result(), snapshot: current)
        model.dismiss(eventID: id(99))
        #expect(model.event?.id == id(2))
        model.dismiss(eventID: id(2))
        model.refresh(snapshot: current)
        #expect(!model.receive(completion: result(), snapshot: current))
        #expect(model.event == nil)
        #expect(!model.claimAnimation(eventID: id(2)))
    }

    @Test("旧关闭和旧动画请求不能影响撤销后新ID")
    func staleActionsCannotAffectRecompletion() throws {
        let model = TodayCompletionCelebrationViewModel()
        model.receive(completion: result(), snapshot: try snapshot([task()]))
        #expect(model.claimAnimation(eventID: id(2)))
        model.refresh(snapshot: try snapshot([task(completionID: nil, status: .pending)]))
        #expect(model.event == nil)
        let latest = try snapshot([task(completionID: 4)])
        #expect(model.receive(completion: result(completionID: 4), snapshot: latest))
        model.dismiss(eventID: id(2))
        #expect(model.event?.id == id(4))
        #expect(!model.claimAnimation(eventID: id(2)))
        #expect(model.claimAnimation(eventID: id(4)))
        #expect(!model.claimAnimation(eventID: id(4)))
        #expect(!model.receive(completion: result(), snapshot: latest))
        #expect(model.event?.id == id(4))
    }

    @Test("资格读取失败显式撤下，恢复查询不补播")
    func invalidationPreservesDeduplication() throws {
        let model = TodayCompletionCelebrationViewModel()
        let current = try snapshot([task()])
        model.receive(completion: result(), snapshot: current)
        model.invalidate()
        model.refresh(snapshot: current)
        #expect(!model.receive(completion: result(), snapshot: current))
        #expect(model.event == nil)
    }

    @Test("日期变化或历史查询撤下旧事件", arguments: [false, true])
    func dayChangesInvalidateEvent(historical: Bool) throws {
        let model = TodayCompletionCelebrationViewModel()
        let current = try snapshot([task()])
        model.receive(completion: result(), snapshot: current)
        model.refresh(snapshot: try snapshot([task()], date: day(historical ? 7 : 8), isCurrent: !historical))
        #expect(model.event == nil)
        model.refresh(snapshot: current)
        #expect(model.event == nil)
    }

    @Test("数量变化即使仍全完成也撤下旧仪式，不悄悄更新事件")
    func changedCountCannotRewriteCurrentEvent() throws {
        let model = TodayCompletionCelebrationViewModel()
        model.receive(completion: result(), snapshot: try snapshot([task()]))
        model.refresh(snapshot: try snapshot([task(), task(taskID: 3, completionID: 4)]))
        #expect(model.event == nil)
    }

    @Test("等待和未完跨日撤下事件", arguments: [false, true])
    func waitingOrCarryOverInvalidatesEvent(carryOver: Bool) throws {
        let model = TodayCompletionCelebrationViewModel()
        model.receive(completion: result(), snapshot: try snapshot([task()]))
        let waiting = TaskSubmissionSnapshot(
            id: id(5), submittedAt: instant, state: .waiting, reviewedAt: nil,
            timing: .beforeReminder, activeDurationSeconds: 0, expectedXP: 0, expectedCoins: 0)
        model.refresh(
            snapshot: try snapshot(
                [task(submission: carryOver ? nil : waiting)],
                carryOver: carryOver ? [task(taskID: 3, completionID: nil, status: .inProgress, date: day(6))] : []))
        #expect(model.event == nil)
    }

    @Test("新审核和零奖励同样仅生成一次纯仪式", arguments: [0, 7])
    func newApprovalCreatesOnlyOneEvent(amount: Int) throws {
        let model = TodayCompletionCelebrationViewModel()
        let current = try snapshot([approvedTask()])
        #expect(model.receive(review: review(amount: amount), snapshot: current))
        #expect(model.event?.id == id(2))
        #expect(model.claimAnimation(eventID: id(2)))
        #expect(!model.receive(review: review(amount: amount), snapshot: current))
        #expect(!model.claimAnimation(eventID: id(2)))
    }

    @Test("等待退回和已冲正审核不创建新仪式", arguments: [SubmissionReviewState.waiting, .returned, .approved])
    func nonEffectiveApprovalCannotCreateEvent(state: SubmissionReviewState) throws {
        let model = TodayCompletionCelebrationViewModel()
        #expect(
            !model.receive(
                review: review(state: state, revoked: state == .approved), snapshot: try snapshot([approvedTask()])))
        #expect(model.event == nil)
    }

    @Test("幂等历史审核不消费真正后来的新回调资格")
    func idempotentReviewDoesNotConsumeNewResult() throws {
        let model = TodayCompletionCelebrationViewModel()
        let current = try snapshot([approvedTask()])
        #expect(!model.receive(review: review(didReview: false), snapshot: current))
        #expect(model.receive(review: review(), snapshot: current))
    }

    @Test("不同入口不能用相同完成ID重复授予")
    func completionIdentityDeduplicatesAcrossEntryPoints() throws {
        let model = TodayCompletionCelebrationViewModel()
        model.receive(completion: result(), snapshot: try snapshot([task()]))
        #expect(!model.receive(review: review(), snapshot: try snapshot([approvedTask()])))
        #expect(model.event == nil)
    }

    @Test("事实已失效时即使只是旧回调也必须撤下现有事件")
    func staleCallbackStillValidatesCurrentFacts() throws {
        let model = TodayCompletionCelebrationViewModel()
        model.receive(completion: result(), snapshot: try snapshot([task()]))
        #expect(!model.receive(completion: result(didComplete: false), snapshot: try snapshot([])))
        #expect(model.event == nil)
    }

    private let instant = Date(timeIntervalSinceReferenceDate: 812_000_000)

    @Test("新结果资格读取失败也消费ID，恢复后不能补播，另一新ID仍可出现")
    func failedQualificationConsumesNewIdentity() throws {
        let model = TodayCompletionCelebrationViewModel()
        model.invalidate(consuming: id(2))
        #expect(!model.receive(completion: result(), snapshot: try snapshot([task()])))
        #expect(model.event == nil)
        #expect(model.receive(completion: result(completionID: 4), snapshot: try snapshot([task(completionID: 4)])))
        #expect(model.event?.id == id(4))
    }

    private func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    private func day(_ value: Int = 7) throws -> LocalDate {
        try LocalDate(year: 2026, month: 10, day: value)
    }

    private func result(completionID: UInt8 = 2, didComplete: Bool = true) -> TaskCompletionResult {
        TaskCompletionResult(
            completionID: id(completionID), completedAt: instant, timing: .beforeReminder,
            xp: 0, coins: 0, didComplete: didComplete)
    }

    private func review(
        state: SubmissionReviewState = .approved, didReview: Bool = true, revoked: Bool = false, amount: Int = 0
    ) -> TaskSubmissionReviewResult {
        TaskSubmissionReviewResult(
            submissionID: id(5), state: state, submittedAt: instant, reviewedAt: instant, completionID: id(2),
            timing: .beforeReminder, xp: amount, coins: amount, rewardIsRevoked: revoked, didReview: didReview)
    }

    private func task(
        taskID: UInt8 = 1, completionID: UInt8? = 2, status: TaskOccurrenceStatus = .completed,
        date: LocalDate? = nil, source: CompletionSource = .childManual,
        verification: TaskVerificationType = .selfConfirm, submission: TaskSubmissionSnapshot? = nil
    ) throws -> TodayTaskItem {
        TodayTaskItem(
            id: id(taskID), date: try date ?? day(), scheduledAt: instant, title: "合成任务", iconName: "book",
            colorToken: "blue", targetDurationSeconds: 60, status: status, origin: .generated(templateRevision: 1),
            activeSessionState: nil, activeDurationSeconds: 0,
            completion: completionID.map {
                TodayTaskCompletion(id: id($0), completedAt: instant, activeDurationSeconds: 0, source: source)
            },
            submission: submission, verificationType: verification)
    }

    private func approvedTask() throws -> TodayTaskItem {
        try task(
            source: .parentApproval, verification: .parentApproval,
            submission: TaskSubmissionSnapshot(
                id: id(5), submittedAt: instant, state: .approved, reviewedAt: instant,
                timing: .beforeReminder, activeDurationSeconds: 0, expectedXP: 0, expectedCoins: 0))
    }

    private func snapshot(
        _ tasks: [TodayTaskItem], date: LocalDate? = nil, isCurrent: Bool = true, carryOver: [TodayTaskItem] = []
    ) throws -> TodayTasksSnapshot {
        let effective = tasks.filter { $0.status != .skipped }
        return TodayTasksSnapshot(
            date: try date ?? day(), isCurrentDate: isCurrent, tasks: tasks, carryOverTasks: carryOver,
            recommendedTaskID: nil, completedCount: effective.count { $0.status == .completed },
            totalCount: effective.count)
    }
}
