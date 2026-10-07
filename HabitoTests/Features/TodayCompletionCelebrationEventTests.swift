import Foundation
import Testing
@testable import Habito

@Suite("今日动态完成纯资格")
struct TodayCompletionCelebrationEventTests {
    @Test("新确认与正数真实全完成记录相符才保留ID日期数量", arguments: [1, 3, 10])
    func newCompletionMatchesActualFinishedTasks(count: Int) throws {
        let tasks = try (1...count).map { try task(taskID: UInt8($0), completionID: UInt8($0 + 64)) }
        let event = try #require(
            TodayCompletionCelebrationEvent(completion: result(completionID: 65), snapshot: snapshot(tasks)))
        #expect(event.id == id(65))
        #expect(event.date == (try day()))
        #expect(event.completedCount == count)
    }

    @Test("零奖励和自主性不同仍只肯定真实完成，不携带财务字段", arguments: [0, 7])
    func currencyDoesNotDecideCompletionEligibility(amount: Int) throws {
        let value = TaskCompletionResult(
            completionID: id(2), completedAt: instant, timing: .afterReminder,
            xp: amount, coins: amount, didComplete: true)
        #expect(TodayCompletionCelebrationEvent(completion: value, snapshot: try snapshot([task()])) != nil)
    }

    @Test("同完成ID重复构造是相等纯值，不变成不同动画身份")
    func repeatedConstructionPreservesIdentity() throws {
        let saved = try snapshot([task()])
        let first = try #require(TodayCompletionCelebrationEvent(completion: result(), snapshot: saved))
        let repeated = try #require(TodayCompletionCelebrationEvent(completion: result(), snapshot: saved))
        #expect(first == repeated)
        #expect(first.id == repeated.id)
    }

    @Test("幂等旧确认结果不能请求新仪式")
    func oldCompletionDoesNotRequestNewEvent() throws {
        #expect(
            TodayCompletionCelebrationEvent(completion: result(didComplete: false), snapshot: try snapshot([task()]))
                == nil)
    }

    @Test("新审核通过必须关联同一提交完成ID", arguments: [0, 7])
    func newApprovalMatchesSubmissionAndCompletion(amount: Int) throws {
        let event = try #require(
            TodayCompletionCelebrationEvent(review: review(amount: amount), snapshot: try snapshot([approvedTask()])))
        #expect(event.id == id(2))
        #expect(event.completedCount == 1)
    }

    @Test("幂等旧审核或已撤销审核结果不能演新通关", arguments: [false, true])
    func oldOrRevokedApprovalDoesNotRequestEvent(revoked: Bool) throws {
        #expect(
            TodayCompletionCelebrationEvent(
                review: review(didReview: revoked, revoked: revoked), snapshot: try snapshot([approvedTask()])) == nil)
    }

    @Test("审核等待退回不是通过", arguments: [SubmissionReviewState.waiting, .returned])
    func nonApprovedReviewDoesNotQualify(state: SubmissionReviewState) throws {
        #expect(
            TodayCompletionCelebrationEvent(review: review(state: state), snapshot: try snapshot([approvedTask()]))
                == nil)
    }

    @Test("通过结果缺完成ID或原提交ID不符必须拒绝", arguments: [false, true])
    func malformedApprovalDoesNotMatchTask(missingCompletion: Bool) throws {
        let value = review(submissionID: missingCompletion ? 5 : 9, completionID: missingCompletion ? nil : 2)
        #expect(TodayCompletionCelebrationEvent(review: value, snapshot: try snapshot([approvedTask()])) == nil)
    }

    @Test("当前快照不同完成ID不能拿来证明这次成功")
    func unrelatedCompletionDoesNotQualify() throws {
        #expect(
            TodayCompletionCelebrationEvent(completion: result(completionID: 9), snapshot: try snapshot([task()]))
                == nil)
    }

    @Test("家长更正或审核事实不能伪装为孩子自行确认", arguments: [CompletionSource.parentCorrection, .parentApproval])
    func confirmationSourceMustMatchReceipt(source: CompletionSource) throws {
        #expect(
            TodayCompletionCelebrationEvent(completion: result(), snapshot: try snapshot([task(source: source)])) == nil
        )
    }

    @Test("验收方式不符不能套用另一事务入口")
    func verificationMustMatchEntryPoint() throws {
        #expect(
            TodayCompletionCelebrationEvent(
                completion: result(), snapshot: try snapshot([task(verification: .parentApproval)])) == nil)
        #expect(TodayCompletionCelebrationEvent(review: review(), snapshot: try snapshot([task()])) == nil)
    }

    @Test("无任务或全跳过不生成仪式", arguments: [false, true])
    func emptyOrSkippedDayDoesNotQualify(skipped: Bool) throws {
        let tasks = skipped ? [try task(status: .skipped)] : []
        #expect(TodayCompletionCelebrationEvent(completion: result(), snapshot: try snapshot(tasks)) == nil)
    }

    @Test("被跳过的触发ID不能借其他已完成任务生成仪式")
    func skippedTriggerDoesNotBorrowAnotherTasksCompletion() throws {
        let tasks = [try task(status: .skipped), try task(taskID: 3, completionID: 4)]
        #expect(TodayCompletionCelebrationEvent(completion: result(), snapshot: try snapshot(tasks)) == nil)
    }

    @Test("未完成或缺当前完成记录不能被聚合计数洗白", arguments: [TaskOccurrenceStatus.pending, .inProgress, .completed])
    func missingConfirmedFactDoesNotQualify(status: TaskOccurrenceStatus) throws {
        let tasks = [try task(), try task(taskID: 3, completionID: nil, status: status)]
        #expect(
            TodayCompletionCelebrationEvent(completion: result(), snapshot: try snapshot(tasks, completed: 2)) == nil)
    }

    @Test("尚有跨日活动任务时不通关")
    func unfinishedCarryOverBlocksEligibility() throws {
        let carryOver = try task(taskID: 3, completionID: nil, status: .inProgress, date: day(day: 6))
        #expect(
            TodayCompletionCelebrationEvent(
                completion: result(), snapshot: try snapshot([task()], carryOver: [carryOver])) == nil)
    }

    @Test("历史日期查询或不属于今日的完成记录不能用于今天", arguments: [false, true])
    func wrongLocalDayDoesNotQualify(historicalQuery: Bool) throws {
        let tasks = [try task(date: historicalQuery ? day() : day(day: 6))]
        #expect(
            TodayCompletionCelebrationEvent(
                completion: result(), snapshot: try snapshot(tasks, isCurrent: !historicalQuery)) == nil)
    }

    @Test("坏完成计数不能替代实际任务事实", arguments: [-1, 0, 2, 3])
    func wrongAggregateCountDoesNotQualify(count: Int) throws {
        #expect(
            TodayCompletionCelebrationEvent(completion: result(), snapshot: try snapshot([task()], completed: count))
                == nil)
    }

    @Test("总数大于实际有效行或负数同样拒绝", arguments: [-1, 0, 2])
    func totalMustMatchActualTasks(total: Int) throws {
        #expect(
            TodayCompletionCelebrationEvent(
                completion: result(), snapshot: try snapshot([task()], completed: total, total: total)) == nil)
    }

    @Test("重复实例ID不能凑通关数量")
    func duplicateOccurrenceDoesNotQualify() throws {
        #expect(
            TodayCompletionCelebrationEvent(
                completion: result(), snapshot: try snapshot([task(), task(completionID: 4)])) == nil)
    }

    @Test("两个实例共用完成ID不能凑通关数量")
    func duplicateCompletionDoesNotQualify() throws {
        #expect(
            TodayCompletionCelebrationEvent(completion: result(), snapshot: try snapshot([task(), task(taskID: 3)]))
                == nil)
    }

    @Test("完成状态仍等待或提交关联已退回不能生成审核仪式", arguments: [SubmissionReviewState.waiting, .returned])
    func approvalRequiresCurrentApprovedSubmission(state: SubmissionReviewState) throws {
        #expect(
            TodayCompletionCelebrationEvent(review: review(), snapshot: try snapshot([approvedTask(state: state)]))
                == nil)
    }

    @Test("其他任务仍等待时不能把完成计数当通关")
    func anotherWaitingTaskBlocksConfirmationEligibility() throws {
        let waiting = TaskSubmissionSnapshot(
            id: id(5), submittedAt: instant, state: .waiting, reviewedAt: nil,
            timing: .beforeReminder, activeDurationSeconds: 0, expectedXP: 0, expectedCoins: 0)
        let tasks = [try task(), try task(taskID: 3, completionID: 4, submission: waiting)]
        #expect(TodayCompletionCelebrationEvent(completion: result(), snapshot: try snapshot(tasks)) == nil)
    }

    private let instant = Date(timeIntervalSinceReferenceDate: 812_000_000)

    private func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    private func day(day: Int = 7) throws -> LocalDate {
        try LocalDate(year: 2026, month: 10, day: day)
    }

    private func result(completionID: UInt8 = 2, didComplete: Bool = true) -> TaskCompletionResult {
        TaskCompletionResult(
            completionID: id(completionID), completedAt: instant, timing: .beforeReminder,
            xp: 0, coins: 0, didComplete: didComplete)
    }

    private func review(
        submissionID: UInt8 = 5, completionID: UInt8? = 2, state: SubmissionReviewState = .approved,
        didReview: Bool = true, revoked: Bool = false, amount: Int = 0
    ) -> TaskSubmissionReviewResult {
        TaskSubmissionReviewResult(
            submissionID: id(submissionID), state: state, submittedAt: instant, reviewedAt: instant,
            completionID: completionID.map(id), timing: .beforeReminder, xp: amount, coins: amount,
            rewardIsRevoked: revoked, didReview: didReview)
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

    private func approvedTask(state: SubmissionReviewState = .approved) throws -> TodayTaskItem {
        try task(
            source: .parentApproval, verification: .parentApproval,
            submission: TaskSubmissionSnapshot(
                id: id(5), submittedAt: instant, state: state, reviewedAt: instant,
                timing: .beforeReminder, activeDurationSeconds: 0, expectedXP: 0, expectedCoins: 0))
    }

    private func snapshot(
        _ tasks: [TodayTaskItem], carryOver: [TodayTaskItem] = [], isCurrent: Bool = true,
        completed: Int? = nil, total: Int? = nil
    ) throws -> TodayTasksSnapshot {
        let effective = tasks.filter { $0.status != .skipped }
        return TodayTasksSnapshot(
            date: try day(), isCurrentDate: isCurrent, tasks: tasks, carryOverTasks: carryOver,
            recommendedTaskID: nil, completedCount: completed ?? effective.count { $0.status == .completed },
            totalCount: total ?? effective.count)
    }
}
