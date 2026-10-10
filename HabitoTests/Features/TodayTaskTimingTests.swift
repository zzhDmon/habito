import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("儿童只读时间快照与截止提示")
struct TodayTaskTimingTests {
    @Test("展示只消费快照和注入时刻，独立时间与两页面一致且不写库", arguments: Array(0..<4), [-1.0, 0.0, 1.0])
    func presentationUsesInjectedClockWithoutWrites(configuration: Int, offset: TimeInterval) throws {
        let hasPlan = configuration & 1 != 0
        let hasDeadline = configuration & 2 != 0
        let fixture = try TodayQueryFixture()
        let row = fixture.makeOccurrence(title: "三个时间展示", scheduledAt: fixture.now, status: .pending)
        row.plannedAt = hasPlan ? fixture.now.addingTimeInterval(-3600) : nil
        row.deadlineAt = hasDeadline ? fixture.now.addingTimeInterval(3600) : nil
        try fixture.context.save()
        let task = navigation(try query(fixture).item(id: row.id, at: fixture.now), fixture: fixture)
        let now = fixture.now.addingTimeInterval(3600 + offset)
        let today = TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: now))
        let session = TaskSessionViewModel(
            occurrenceID: row.id, context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: now))
        let expected = KidTaskTimingPresentation(task: task, at: now)
        #expect(today.makeTimingPresentation(for: task) == expected)
        #expect(session.makeTimingPresentation(for: task) == expected)
        #expect(expected.taskID == row.id && expected.reminderText == "提醒时间 12:00")
        #expect(expected.plannedText == (hasPlan ? "计划时间 11:00" : nil))
        #expect(expected.deadlineText == (hasDeadline ? "截止时间 13:00" : nil))
        #expect(expected.showsDeadlineHint == (hasDeadline && offset > 0))
        #expect(expected.needsDeadlineRefresh == hasDeadline)
        #expect(row.status == .pending && !fixture.context.hasChanges)
        try expectNoRewards(fixture.context)
        // 展示刷新不能保存、回滚或丢掉调用者尚未保存的编辑。
        row.titleSnapshot = "未保存的修改"
        _ = today.makeTimingPresentation(for: task)
        _ = session.makeTimingPresentation(for: task)
        #expect(fixture.context.hasChanges && row.titleSnapshot == "未保存的修改")
    }

    @Test("跨日执行页保留原实例与累计时间，一日前和两日前均使用通用文案", arguments: [1, 2])
    func sessionCarryOverUsesBusinessDate(days: Int) throws {
        let fixture = try TodayQueryFixture()
        let earlier = fixture.now.addingTimeInterval(-Double(days) * 86400)
        let row = fixture.makeOccurrence(
            title: "跨日任务", scheduledAt: earlier, status: .inProgress,
            date: try LocalDate(date: earlier, calendar: fixture.calendar, timeZone: fixture.timeZone))
        fixture.addSession(to: row, state: .paused, startedAt: earlier, lastResumedAt: earlier, accumulatedSeconds: 300)
        try fixture.context.save()
        let model = TaskSessionViewModel(
            occurrenceID: row.id, context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now))
        model.load()
        guard case let .loaded(content) = model.state else { Issue.record("跨日页应成功加载"); return }
        #expect(content.task.id == row.id && content.task.isCarryOver)
        #expect(content.task.statusText == "之前的任务：已暂停" && content.activeDurationAtSnapshot == 300)
        #expect(content.primaryAction == .resume && content.canComplete && !fixture.context.hasChanges)
        try expectNoRewards(fixture.context)
    }

    @Test("独立可空快照不由提醒补值，首页和单项返回同一时间", arguments: [false, true], [false, true])
    func optionalTimesPropagateWithoutFallback(hasPlan: Bool, hasDeadline: Bool) throws {
        let fixture = try TodayQueryFixture()
        let row = fixture.makeOccurrence(title: "三个独立时间", scheduledAt: fixture.now, status: .pending)
        row.plannedAt = hasPlan ? fixture.now.addingTimeInterval(-3600) : nil
        row.deadlineAt = hasDeadline ? fixture.now.addingTimeInterval(3600) : nil
        try fixture.context.save()
        let service = query(fixture)
        let item = try service.item(id: row.id, at: fixture.now)
        let snapshot = try service.snapshot(for: fixture.date, at: fixture.now)
        #expect(snapshot.tasks.first?.timing == item.timing)
        #expect(item.timing.plannedAt == row.plannedAt && item.timing.deadlineAt == row.deadlineAt)
        let route = navigation(item, fixture: fixture)
        #expect(route.scheduledTimeText == "12:00")
        #expect(route.plannedTimeText == (hasPlan ? "11:00" : nil))
        #expect(route.deadlineTimeText == (hasDeadline ? "13:00" : nil))
        #expect(route.timing == item.timing && !route.timing.isPastDeadline(at: fixture.now))
        #expect(snapshot.recommendedTaskID == row.id && snapshot.totalCount == 1 && snapshot.completedCount == 0)
        try expectNoRewards(fixture.context)
        #expect(!fixture.context.hasChanges)
    }

    @Test("坏绝对时刻在格式化之前明确拒绝，查询不回滚用户值", arguments: [0, 1, 2], [Double.nan, Double.infinity, -Double.infinity])
    func nonfiniteTimesFailWithoutMutation(field: Int, value: Double) throws {
        let fixture = try TodayQueryFixture()
        let row = fixture.makeOccurrence(title: "坏时刻", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        // 不靠 SQLite 对 NaN 的编码行为制造夹具；直接验证已载入的坏模型值与只读边界。
        let invalid = Date(timeIntervalSinceReferenceDate: value)
        if field == 0 { row.scheduledAt = invalid }
        if field == 1 { row.plannedAt = invalid }
        if field == 2 { row.deadlineAt = invalid }
        let error = TodayTaskQueryError.invalidOccurrenceTime(
            occurrenceID: row.id, field: ["scheduledAt", "plannedAt", "deadlineAt"][field])
        let service = query(fixture)
        #expect(throws: error) { try service.item(id: row.id, at: fixture.now) }
        #expect(throws: error) { try service.snapshot(for: fixture.date, at: fixture.now) }
        #expect(fixture.context.hasChanges)
        let retained = [Optional(row.scheduledAt), row.plannedAt, row.deadlineAt][field]
        #expect(try #require(retained).timeIntervalSinceReferenceDate.isFinite == false)
        try expectNoRewards(fixture.context)
    }

    @Test("严格晚于截止且仅可执行状态提示，执行权限和等待事实不变", arguments: Array(0..<6), [-1.0, 0.0, 1.0])
    func deadlineHintPreservesTaskActions(kind: Int, offset: TimeInterval) throws {
        let fixture = try TodayQueryFixture()
        let status: TaskOccurrenceStatus =
            switch kind {
            case 1: .inProgress
            case 2: .completed
            case 3: .skipped
            default: .pending
            }
        let row = fixture.makeOccurrence(
            title: "截止只提示", scheduledAt: fixture.now.addingTimeInterval(600), status: status)
        row.deadlineAt = fixture.now
        if kind == 1 {
            fixture.addSession(
                to: row, state: .paused, startedAt: fixture.now.addingTimeInterval(-120),
                lastResumedAt: fixture.now.addingTimeInterval(-120), accumulatedSeconds: 60)
        }
        if kind == 2 { fixture.addCompletion(to: row, at: fixture.now.addingTimeInterval(-120)) }
        if kind >= 4 { row.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue }
        try fixture.context.save()
        if kind >= 4 {
            let receipt = try TaskSubmissionService(context: fixture.context).submit(
                row, at: fixture.now.addingTimeInterval(-120))
            if kind == 5 {
                _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
                    row, submissionID: receipt.submissionID, at: fixture.now.addingTimeInterval(-60))
            }
        }
        let now = fixture.now.addingTimeInterval(offset)
        let item = try query(fixture).item(id: row.id, at: now)
        let route = navigation(item, fixture: fixture)
        let actionable = kind == 0 || kind == 1 || kind == 5
        #expect(route.timing.isPastDeadline(at: now) == (actionable && offset > 0))
        #expect(KidTaskTimingPresentation(task: route, at: now).showsDeadlineHint == (actionable && offset > 0))
        #expect(KidTaskTimingPresentation(task: route, at: now).needsDeadlineRefresh == actionable)
        let content = TaskSessionScreenContent(
            task: route, targetDurationSeconds: item.targetDurationSeconds, activeSessionState: item.activeSessionState,
            activeDurationAtSnapshot: item.activeDurationSeconds, snapshotAt: now, completion: item.completion,
            submission: item.submission, verificationType: item.verificationType)
        #expect(content.canComplete == actionable)
        #expect(content.isAwaitingReview == (kind == 4))
        #expect(row.status == status && row.deadlineAt == fixture.now)
        try expectNoRewards(fixture.context)
        #expect(!fixture.context.hasChanges)
    }

    @Test("计划/截止不参与推荐排序或今日进度，刷新只换提示快照")
    func optionalTimesDoNotReorderTasksOrProgress() throws {
        let fixture = try TodayQueryFixture()
        let first = fixture.makeOccurrence(
            title: "提醒先到", scheduledAt: fixture.now.addingTimeInterval(-60), status: .pending)
        let second = fixture.makeOccurrence(
            title: "提醒未到", scheduledAt: fixture.now.addingTimeInterval(600), status: .pending)
        first.plannedAt = fixture.now.addingTimeInterval(3600)
        first.deadlineAt = fixture.now.addingTimeInterval(3600)
        second.plannedAt = fixture.now.addingTimeInterval(-3600)
        second.deadlineAt = fixture.now.addingTimeInterval(-3600)
        try fixture.context.save()
        let before = try query(fixture).snapshot(for: fixture.date, at: fixture.now)
        #expect(before.tasks.map(\.id) == [first.id, second.id] && before.recommendedTaskID == first.id)
        first.deadlineAt = fixture.now.addingTimeInterval(-120)
        try fixture.context.save()
        let model = TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now))
        model.load()
        guard case let .loaded(content) = model.state else { Issue.record("预期首页可读时间"); return }
        #expect(
            content.recommendedTask?.id == first.id
                && content.recommendedTask?.timing.isPastDeadline(at: fixture.now) == true)
        #expect(content.remainingTasks.map(\.id) == [second.id])
        #expect(content.completedCount == 0 && content.totalCount == 2)
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        try expectNoRewards(fixture.context)
        #expect(!fixture.context.hasChanges)
    }

    @Test("三个时刻共用注入时区而非设备时区")
    func navigationUsesInjectedTimeZoneForAllTimes() throws {
        let fixture = try TodayQueryFixture()
        let row = fixture.makeOccurrence(title: "注入时区", scheduledAt: fixture.now, status: .pending)
        row.plannedAt = fixture.now.addingTimeInterval(-3600)
        row.deadlineAt = fixture.now.addingTimeInterval(3600)
        try fixture.context.save()
        let item = try query(fixture).item(id: row.id, at: fixture.now)
        var calendar = fixture.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let route = KidTaskNavigationItem(item: item, calendar: calendar)
        #expect(
            route.scheduledTimeText == "21:00" && route.plannedTimeText == "20:00" && route.deadlineTimeText == "22:00")
        #expect(route.timing == item.timing)
    }

    @Test("两日前进行中保留真实截止，仍可恢复且不混今日分母")
    func multiDayCarryOverKeepsTimingAndProgress() throws {
        let fixture = try TodayQueryFixture()
        let earlier = fixture.now.addingTimeInterval(-172800)
        let row = fixture.makeOccurrence(
            title: "之前继续", scheduledAt: earlier, status: .inProgress,
            date: try LocalDate(dateKey: "2026-09-21"))
        row.plannedAt = earlier.addingTimeInterval(-600)
        row.deadlineAt = earlier.addingTimeInterval(600)
        fixture.addSession(to: row, state: .paused, startedAt: earlier, lastResumedAt: earlier, accumulatedSeconds: 60)
        try fixture.context.save()
        let snapshot = try query(fixture).snapshot(for: fixture.date, at: fixture.now)
        let item = try #require(snapshot.carryOverTasks.first)
        let route = navigation(item, fixture: fixture)
        #expect(
            route.isCarryOver && route.timing.plannedAt == row.plannedAt && route.timing.deadlineAt == row.deadlineAt)
        #expect(route.timing.isPastDeadline(at: fixture.now))
        #expect(snapshot.recommendedTaskID == row.id && snapshot.totalCount == 0 && snapshot.completedCount == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("已超过截止仍真实完成，奖励与自主只按提醒边界", arguments: [-60.0, 0.0, 60.0])
    func completionAfterDeadlineUsesReminderForActualReward(reminderOffset: TimeInterval) throws {
        let fixture = try TodayQueryFixture()
        let row = fixture.makeOccurrence(
            title: "仍然可以完成", scheduledAt: fixture.now.addingTimeInterval(reminderOffset), status: .pending)
        row.plannedAt = fixture.now.addingTimeInterval(500)
        row.deadlineAt = fixture.now.addingTimeInterval(-120)
        // 合成显式金额用于断言真实收据，不是产品默认。
        row.xpRewardSnapshot = 11
        row.coinRewardSnapshot = 7
        row.activeBonusCoinSnapshot = 3
        try fixture.context.save()
        #expect(try query(fixture).item(id: row.id, at: fixture.now).timing.isPastDeadline(at: fixture.now))
        let receipt = try TaskCompletionService(context: fixture.context).complete(
            row, at: fixture.now, source: .childManual)
        #expect(receipt.didComplete && receipt.xp == 11 && receipt.coins == (reminderOffset > 0 ? 10 : 7))
        #expect(receipt.timing == (reminderOffset > 0 ? .beforeReminder : .afterReminder))
        let completed = try query(fixture).item(id: row.id, at: fixture.now)
        #expect(!completed.timing.isPastDeadline(at: fixture.now) && completed.status == .completed)
        let repeated = try TaskCompletionService(context: fixture.context).complete(
            row, at: fixture.now, source: .childManual)
        #expect(!repeated.didComplete && repeated.completionID == receipt.completionID)
        #expect(
            try RewardLedgerService(context: fixture.context).balance()
                == RewardBalance(effectiveXP: 11, coins: receipt.coins))
    }

    @Test("旧冻结库与正式新配置两次重开只读一致，不填旧时间或写奖励", arguments: [false, true])
    func oldAndNewDiskTimingRemainReadOnly(legacy: Bool) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let fixture = try TodayQueryFixture()
        let id: UUID
        if legacy {
            try V0MigrationFixture.seed(at: url)
            id = V0MigrationFixture.pendingID
        } else {
            id = try seedConfiguredTimeStore(at: url, fixture: fixture)
        }
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            let service = TodayTaskQueryService(
                context: context, calendar: fixture.calendar, timeZone: fixture.timeZone)
            let item = try service.item(id: id, at: fixture.now)
            let route = navigation(item, fixture: fixture)
            #expect(route.id == id && route.plannedTimeText == (legacy ? nil : "08:00"))
            #expect(route.deadlineTimeText == (legacy ? nil : "11:00"))
            #expect(route.timing.isPastDeadline(at: fixture.now) == !legacy)
            #expect(try service.snapshot(for: fixture.date, at: fixture.now).tasks.contains { $0.id == id })
            try expectNoRewards(context)
            #expect(!context.hasChanges)
        }
    }

    private func query(_ fixture: TodayQueryFixture) -> TodayTaskQueryService {
        TodayTaskQueryService(context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
    }

    private func navigation(_ item: TodayTaskItem, fixture: TodayQueryFixture) -> KidTaskNavigationItem {
        var calendar = fixture.calendar
        calendar.timeZone = fixture.timeZone
        return KidTaskNavigationItem(item: item, calendar: calendar, referenceDate: fixture.date)
    }

    private func expectNoRewards(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }

    /// 正式保存事务写合成库，重开阶段只传稳定实例 ID。
    private func seedConfiguredTimeStore(at url: URL, fixture: TodayQueryFixture) throws -> UUID {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        var draft = TaskTemplateDraft.new
        draft.title = "正式时间快照"
        draft.plannedTimeOfDayMinutes = 480
        draft.deadlineTimeOfDayMinutes = 660
        _ = try TaskTemplateEditingService(context: context, calendar: fixture.calendar, timeZone: fixture.timeZone)
            .save(draft, at: fixture.now)
        return try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first).id
    }
}
