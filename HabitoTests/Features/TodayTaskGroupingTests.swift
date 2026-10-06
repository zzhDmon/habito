import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("今日时间段只读投影")
struct TodayTaskGroupingTests {
    @Test("四个显式时段保持快照，不由早晚提醒钟点推断", arguments: TaskTimePeriod.allCases, [-11, 7])
    func explicitPeriodIgnoresReminderHour(period: TaskTimePeriod, hourOffset: Int) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(
            title: "明确时段", scheduledAt: fixture.now.addingTimeInterval(Double(hourOffset) * 3600), status: .pending)
        occurrence.timePeriodSnapshotRawValue = period.rawValue
        try fixture.context.save()
        let service = TodayTaskQueryService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
        let item = try service.item(id: occurrence.id, at: fixture.now)
        #expect(item.timePeriod == period)
        #expect(try fixture.snapshot().tasks.first?.timePeriod == period)
        let route = KidTaskNavigationItem(item: item, calendar: fixture.calendar, referenceDate: fixture.date)
        #expect(route.id == occurrence.id && route.timePeriod == period && !route.isCarryOver)
        #expect(!fixture.context.hasChanges)
    }

    @Test("非法时间段单项与整页明确失败，不改存储或伪造全天", arguments: ["", "unknown"])
    func invalidPeriodFailsBothQueries(value: String) throws {
        let fixture = try TodayQueryFixture()
        let occurrence = fixture.makeOccurrence(title: "坏时段", scheduledAt: fixture.now, status: .pending)
        occurrence.timePeriodSnapshotRawValue = value
        try fixture.context.save()
        let service = TodayTaskQueryService(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone)
        let error = TodayTaskQueryError.invalidTimePeriod(occurrenceID: occurrence.id, value: value)
        #expect(throws: error) { try service.item(id: occurrence.id, at: fixture.now) }
        #expect(throws: error) { try service.snapshot(for: fixture.date, at: fixture.now) }
        let model = makeModel(fixture)
        model.load()
        #expect(model.state == .failed)
        #expect(model.rewardState == .loaded(RewardBalance(effectiveXP: 0, coins: 0)))
        #expect(occurrence.timePeriodSnapshotRawValue == value && !fixture.context.hasChanges)
    }

    @Test("推荐去重、跳过排除、等待和完成保留，组内不改查询排序")
    func groupingPreservesTaskFactsAndOrdering() throws {
        let fixture = try TodayQueryFixture()
        let recommended = makeTask(fixture, period: .allDay, offset: -4000)
        let waiting = makeTask(fixture, period: .morning, offset: -3000)
        waiting.verificationTypeSnapshotRawValue = TaskVerificationType.parentApproval.rawValue
        let morning = makeTask(fixture, period: .morning, offset: 3600)
        let completed = makeTask(fixture, period: .evening, offset: -2000, status: .completed)
        fixture.addCompletion(to: completed, at: fixture.now)
        let evening = makeTask(fixture, period: .evening, offset: 7200)
        let afterSchool = makeTask(fixture, period: .afterSchool, offset: 1800)
        let allDay = makeTask(fixture, period: .allDay, offset: 10800)
        let skipped = makeTask(fixture, period: .morning, offset: -5000, status: .skipped)
        try fixture.context.save()
        _ = try TaskSubmissionService(context: fixture.context).submit(waiting, at: fixture.now)
        let snapshot = try fixture.snapshot()
        let model = makeModel(fixture)
        model.load()
        let content = try loaded(model)
        #expect(content.recommendedTask?.id == recommended.id)
        #expect(content.remainingTaskGroups.map(\.id) == TaskTimePeriod.allCases.map(TodayTaskGroupKind.timePeriod))
        for group in content.remainingTaskGroups {
            guard case let .timePeriod(period) = group.id else {
                Issue.record("今日实例不应进入跨日组")
                continue
            }
            let expected = snapshot.visibleTasks.filter { $0.id != recommended.id && $0.timePeriod == period }
            #expect(group.tasks.map(\.id) == expected.map(\.id))
        }
        let ids = content.remainingTaskGroups.flatMap(\.tasks).map(\.id)
        #expect(Set(ids) == Set([waiting.id, morning.id, completed.id, evening.id, afterSchool.id, allDay.id]))
        #expect(ids.count == Set(ids).count && !ids.contains(recommended.id) && !ids.contains(skipped.id))
        #expect(content.completedCount == 1 && content.totalCount == 7 && !content.isAllCompleted)
        #expect(content.remainingTasks.first { $0.id == waiting.id }?.statusText == "等家长确认")
        try expectNoRewards(fixture.context)
        #expect(!fixture.context.hasChanges)
    }

    @Test("跨日组独立且不重复进入时段组，原进行中推荐与今日进度不变")
    func carryOverDoesNotContaminateTodayGroupsOrProgress() throws {
        let fixture = try TodayQueryFixture()
        let first = fixture.makeOccurrence(
            title: "前日继续", scheduledAt: fixture.now.addingTimeInterval(-172800), status: .inProgress,
            date: try LocalDate(dateKey: "2026-09-21"))
        let second = fixture.makeOccurrence(
            title: "昨日继续", scheduledAt: fixture.now.addingTimeInterval(-86400), status: .inProgress,
            date: try LocalDate(dateKey: "2026-09-22"))
        for task in [first, second] {
            task.timePeriodSnapshotRawValue = TaskTimePeriod.evening.rawValue
            fixture.addSession(
                to: task, state: .paused, startedAt: task.scheduledAt, lastResumedAt: task.scheduledAt,
                accumulatedSeconds: 30)
        }
        let today = makeTask(fixture, period: .morning, offset: 3600)
        try fixture.context.save()
        let model = makeModel(fixture)
        model.load()
        let content = try loaded(model)
        #expect(content.recommendedTask?.id == first.id && content.recommendedTask?.isCarryOver == true)
        #expect(content.remainingTaskGroups.map(\.id) == [.carryOver, .timePeriod(.morning)])
        #expect(content.remainingTaskGroups.first?.tasks.map(\.id) == [second.id])
        #expect(content.remainingTaskGroups.last?.tasks.map(\.id) == [today.id])
        #expect(content.completedCount == 0 && content.totalCount == 1 && !content.isAllCompleted)
        try expectNoRewards(fixture.context)
        #expect(!fixture.context.hasChanges)
    }

    @Test("空组省略，全部完成与旧全天仍保留原状态")
    func emptyAndCompletedGroupingKeepCompatibility() throws {
        let fixture = try TodayQueryFixture()
        let model = makeModel(fixture)
        model.load()
        #expect(try loaded(model).remainingTaskGroups.isEmpty)
        let task = fixture.makeOccurrence(title: "旧全天", scheduledAt: fixture.now, status: .completed)
        fixture.addCompletion(to: task, at: fixture.now)
        try fixture.context.save()
        model.load()
        let content = try loaded(model)
        #expect(content.recommendedTask == nil && content.isAllCompleted)
        #expect(content.remainingTaskGroups.map(\.id) == [.timePeriod(.allDay)])
        #expect(content.remainingTaskGroups.first?.tasks.map(\.id) == [task.id])
    }

    @Test("显式快照更新后重新生成分组，不缓存旧时段或改变稳定任务 ID")
    func refreshRebuildsProjectionFromSavedPeriod() throws {
        let fixture = try TodayQueryFixture()
        let task = makeTask(fixture, period: .morning, offset: 0, status: .completed)
        fixture.addCompletion(to: task, at: fixture.now)
        try fixture.context.save()
        let model = makeModel(fixture)
        model.load()
        #expect(try loaded(model).remainingTaskGroups.map(\.id) == [.timePeriod(.morning)])
        // 只在测试中直接改变显式输入来验证刷新；生产受保护历史仍由原服务拒绝改写。
        task.timePeriodSnapshotRawValue = TaskTimePeriod.afterSchool.rawValue
        try fixture.context.save()
        model.load()
        #expect(try loaded(model).remainingTaskGroups.map(\.id) == [.timePeriod(.afterSchool)])
        #expect(try loaded(model).remainingTaskGroups.first?.tasks.map(\.id) == [task.id])
    }

    @Test("独立旧磁盘库迁移后两次重开，旧全天/活动恢复/稳定身份不变且不补奖")
    func oldStoreReopenKeepsAllDayAndStableProjection() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V0MigrationFixture.seed(at: url)
        let fixture = try TodayQueryFixture()
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            let model = TodayViewModel(
                context: context, calendar: fixture.calendar, timeZone: fixture.timeZone,
                dateProvider: FixedDateProvider(value: fixture.now))
            model.load()
            let content = try loaded(model)
            #expect(content.recommendedTask?.id == V0MigrationFixture.activeID)
            #expect(content.recommendedTask?.timePeriod == .allDay && content.recommendedTask?.isCarryOver == true)
            #expect(content.remainingTaskGroups.map(\.id) == [.timePeriod(.allDay)])
            #expect(content.remainingTaskGroups.first?.tasks.map(\.id) == [V0MigrationFixture.pendingID])
            #expect(content.totalCount == 1 && content.completedCount == 0)
            try expectNoRewards(context)
            #expect(!context.hasChanges)
        }
    }

    @Test("新显式时段磁盘两次重开，分组身份与任务 ID 不变且不写库")
    func configuredStoreReopenKeepsPeriodsAndIDs() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let fixture = try TodayQueryFixture()
        let ids = try seedConfiguredStore(at: url, fixture: fixture)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            let service = TodayTaskQueryService(
                context: context, calendar: fixture.calendar, timeZone: fixture.timeZone)
            let snapshot = try service.snapshot(for: fixture.date, at: fixture.now)
            #expect(snapshot.tasks.map(\.id) == ids)
            #expect(snapshot.tasks.map(\.timePeriod) == TaskTimePeriod.allCases)
            let model = TodayViewModel(
                context: context, calendar: fixture.calendar, timeZone: fixture.timeZone,
                dateProvider: FixedDateProvider(value: fixture.now))
            model.load()
            let content = try loaded(model)
            #expect(content.recommendedTask?.id == ids.first)
            #expect(
                content.remainingTaskGroups.map(\.id) == [
                    .timePeriod(.afterSchool), .timePeriod(.evening), .timePeriod(.allDay),
                ])
            #expect(content.remainingTaskGroups.flatMap(\.tasks).map(\.id) == Array(ids.dropFirst()))
            #expect(content.totalCount == 4 && content.completedCount == 0)
            try expectNoRewards(context)
            #expect(!context.hasChanges)
        }
    }

    /// 跨容器只返回身份；没有把仍连接的模型传到重开容器，也不清理 SQLite 辅助文件。
    private func seedConfiguredStore(at url: URL, fixture: TodayQueryFixture) throws -> [UUID] {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        var ids: [UUID] = []
        for (index, period) in TaskTimePeriod.allCases.enumerated() {
            let task = TaskOccurrence(
                templateID: UUID(), date: fixture.date,
                scheduledAt: fixture.now.addingTimeInterval(Double(index + 1) * 3600),
                titleSnapshot: "显式磁盘时段", iconSnapshot: "book.fill", colorSnapshot: "reading",
                targetDurationSnapshot: 900, sourceRevision: 1, createdAt: fixture.now, updatedAt: fixture.now,
                timePeriodSnapshot: period)
            context.insert(task)
            ids.append(task.id)
        }
        try context.save()
        return ids
    }

    private func makeTask(
        _ fixture: TodayQueryFixture, period: TaskTimePeriod, offset: TimeInterval,
        status: TaskOccurrenceStatus = .pending
    ) -> TaskOccurrence {
        let task = fixture.makeOccurrence(
            title: "固定时段", scheduledAt: fixture.now.addingTimeInterval(offset), status: status)
        task.timePeriodSnapshotRawValue = period.rawValue
        return task
    }

    private func makeModel(_ fixture: TodayQueryFixture) -> TodayViewModel {
        TodayViewModel(
            context: fixture.context, calendar: fixture.calendar, timeZone: fixture.timeZone,
            dateProvider: FixedDateProvider(value: fixture.now))
    }

    private func loaded(_ model: TodayViewModel) throws -> TodayScreenContent {
        guard case let .loaded(content) = model.state else {
            Issue.record("预期只读今日状态加载成功")
            throw NSError(domain: "HabitoSyntheticTodayGroupingState", code: 1)
        }
        return content
    }

    private func expectNoRewards(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
    }
}
