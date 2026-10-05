import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("任务实例幂等核对")
struct TaskOccurrenceReconciliationServiceTests {
    @Test("相同候选连续核对五次不重复且稳定身份")
    func fiveReconciliationsRemainIdempotent() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        try context.save()
        let today = try localDate("2026-09-23")
        let end = try localDate("2026-09-30")
        let candidates = [
            try candidate("2026-09-23", hour: 19, revision: 1),
            try candidate("2026-09-24", hour: 19, revision: 1),
        ]
        let service = TaskOccurrenceReconciliationService(context: context)
        let now = try instant("2026-09-23T01:00:00Z")

        var originalIDs: Set<UUID> = []
        for iteration in 0..<5 {
            let report = try service.reconcile(
                template: template,
                candidates: candidates,
                in: today...end,
                today: today,
                now: now
            )
            let occurrences = try fetchOccurrences(context)

            #expect(occurrences.count == 2)
            #expect(Set(occurrences.map(\.uniquenessKey)).count == 2)
            if iteration == 0 {
                #expect(report.insertedCount == 2)
                originalIDs = Set(occurrences.map(\.id))
            } else {
                #expect(report == .init(insertedCount: 0, updatedCount: 0, deletedCount: 0, protectedCount: 0))
                #expect(Set(occurrences.map(\.id)) == originalIDs)
            }
        }
    }

    @Test("模板修订只原位更新今天和未来的普通待处理实例")
    func templateRevisionUpdatesOnlyMutableOccurrences() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let today = try localDate("2026-09-23")
        let mutable = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let inProgress = try occurrence(template: template, dateKey: "2026-09-25", status: .inProgress)
        let completed = try occurrence(template: template, dateKey: "2026-09-26", status: .completed)
        let skipped = try occurrence(template: template, dateKey: "2026-09-27", status: .skipped)
        let detached = try occurrence(
            template: template,
            dateKey: "2026-09-28",
            status: .pending,
            detached: true
        )
        let past = try occurrence(template: template, dateKey: "2026-09-22", status: .pending)
        [mutable, inProgress, completed, skipped, detached, past].forEach(context.insert)
        try context.save()
        let mutableID = mutable.id

        template.title = "新版阅读"
        template.targetDurationSeconds = 1_200
        template.revision = 2
        template.categoryRawValue = TaskCategory.challenge.rawValue
        template.timePeriodRawValue = TaskTimePeriod.afterSchool.rawValue
        template.verificationTypeRawValue = TaskVerificationType.parentApproval.rawValue
        template.xpReward = 11
        template.coinReward = 7
        template.activeBonusCoin = 3
        let candidates = try ["24", "25", "26", "27", "28"].map {
            try candidate("2026-09-\($0)", hour: 20, revision: 2)
        }
        let report = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: candidates,
            in: localDate("2026-09-22")...localDate("2026-09-30"),
            today: today,
            now: instant("2026-09-23T02:00:00Z")
        )

        #expect(report.updatedCount == 1)
        #expect(report.protectedCount == 5)
        #expect(mutable.id == mutableID)
        #expect(mutable.titleSnapshot == "新版阅读")
        #expect(mutable.targetDurationSnapshot == 1_200)
        #expect(mutable.sourceRevision == 2)
        expectConfiguration(mutable, category: .challenge, period: .afterSchool, verification: .parentApproval)
        for protected in [inProgress, completed, skipped, detached, past] {
            expectConfiguration(
                protected, category: .unassigned, period: .allDay, verification: .selfConfirm, reward: 0)
        }
        #expect(inProgress.titleSnapshot == "阅读")
        #expect(completed.titleSnapshot == "阅读")
        #expect(skipped.titleSnapshot == "阅读")
        #expect(detached.titleSnapshot == "阅读")
        #expect(past.titleSnapshot == "阅读")
    }

    @Test("模板归档只移除范围内未来普通待处理实例")
    func archivedTemplateRemovesOnlyMutableFutureOccurrences() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let removable = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let completed = try occurrence(template: template, dateKey: "2026-09-25", status: .completed)
        let detached = try occurrence(
            template: template,
            dateKey: "2026-09-26",
            status: .pending,
            detached: true
        )
        let outsideRange = try occurrence(template: template, dateKey: "2026-10-02", status: .pending)
        [removable, completed, detached, outsideRange].forEach(context.insert)
        try context.save()
        template.archivedAt = try instant("2026-09-23T03:00:00Z")

        let report = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: [],
            in: localDate("2026-09-23")...localDate("2026-09-30"),
            today: localDate("2026-09-23"),
            now: instant("2026-09-23T03:00:00Z")
        )
        let remaining = try fetchOccurrences(context)

        #expect(report.deletedCount == 1)
        #expect(report.protectedCount == 2)
        #expect(Set(remaining.map(\.id)) == [completed.id, detached.id, outsideRange.id])
    }

    @Test("范围外候选和过期修订会在写入前拒绝")
    func invalidCandidatesAreRejectedBeforeWrite() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        try context.save()
        let today = try localDate("2026-09-23")
        let service = TaskOccurrenceReconciliationService(context: context)

        #expect(throws: OccurrenceReconciliationError.candidateRevisionMismatch(candidate: 2, template: 1)) {
            try service.reconcile(
                template: template,
                candidates: [candidate("2026-09-24", hour: 19, revision: 2)],
                in: today...localDate("2026-09-30"),
                today: today,
                now: instant("2026-09-23T01:00:00Z")
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
    }

    @Test("损坏的存量状态在任何实例被修改前失败")
    func invalidStoredStateDoesNotPartiallyUpdateContext() throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let valid = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let invalid = try occurrence(template: template, dateKey: "2026-09-25", status: .pending)
        invalid.statusRawValue = "unknown"
        context.insert(valid)
        context.insert(invalid)
        try context.save()
        let originalTime = valid.scheduledAt

        #expect(
            throws: OccurrenceReconciliationError.invalidStoredStatus(
                occurrenceID: invalid.id,
                rawValue: "unknown"
            )
        ) {
            try TaskOccurrenceReconciliationService(context: context).reconcile(
                template: template,
                candidates: [
                    candidate("2026-09-24", hour: 20, revision: 1),
                    candidate("2026-09-25", hour: 20, revision: 1),
                ],
                in: localDate("2026-09-23")...localDate("2026-09-30"),
                today: localDate("2026-09-23"),
                now: instant("2026-09-23T04:00:00Z")
            )
        }

        #expect(valid.scheduledAt == originalTime)
        #expect(valid.titleSnapshot == "阅读")
    }

    @Test("所有已有分类时段及两种 P0 验收按显式配置生成，重复核对不更新", arguments: TaskVerificationType.allCases)
    func generatesExplicitConfigurationIdempotently(verification: TaskVerificationType) throws {
        for category in TaskCategory.allCases {
            for period in TaskTimePeriod.allCases {
                let context = try makeContext()
                let template = makeTemplate()
                template.categoryRawValue = category.rawValue
                template.timePeriodRawValue = period.rawValue
                template.verificationTypeRawValue = verification.rawValue
                template.xpReward = 11
                template.coinReward = 7
                template.activeBonusCoin = 3
                context.insert(template)
                try context.save()
                let date = try localDate("2026-09-23")
                let now = try instant("2026-09-23T01:00:00Z")
                let service = TaskOccurrenceReconciliationService(context: context)
                let desired = [try candidate(date.dateKey, hour: 19, revision: 1)]
                let created = try service.reconcile(
                    template: template, candidates: desired, in: date...date, today: date, now: now)
                let row = try #require(fetchOccurrences(context).first)
                let stableID = row.id
                #expect(created.insertedCount == 1)
                expectConfiguration(row, category: category, period: period, verification: verification)
                #expect(row.plannedAt == nil && row.deadlineAt == nil)
                for _ in 0..<3 {
                    let unchanged = try service.reconcile(
                        template: template, candidates: desired, in: date...date, today: date,
                        now: now.addingTimeInterval(60))
                    #expect(unchanged == .init(insertedCount: 0, updatedCount: 0, deletedCount: 0, protectedCount: 0))
                    #expect(row.id == stableID && row.updatedAt == now && !context.hasChanges)
                }
            }
        }
    }

    @Test("任一 V1 配置差异即使未改修订号也被核对，且不改计划截止", arguments: Array(0..<6))
    func eachConfigurationDifferenceIsDetected(field: Int) throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let row = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let plan = try instant("2026-09-24T08:00:00Z")
        let deadline = plan.addingTimeInterval(600)
        row.plannedAt = plan
        row.deadlineAt = deadline
        context.insert(row)
        try context.save()
        switch field {
        case 0: template.categoryRawValue = TaskCategory.growth.rawValue
        case 1: template.timePeriodRawValue = TaskTimePeriod.evening.rawValue
        case 2: template.verificationTypeRawValue = TaskVerificationType.parentApproval.rawValue
        case 3: template.xpReward = 11
        case 4: template.coinReward = 7
        default: template.activeBonusCoin = 3
        }
        try context.save()
        let date = try localDate("2026-09-24")
        let now = try instant("2026-09-23T02:00:00Z")
        let report = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template, candidates: [candidate(date.dateKey, hour: 19, revision: 1)],
            in: date...date, today: localDate("2026-09-23"), now: now)
        #expect(report.updatedCount == 1 && report.insertedCount == 0)
        #expect(row.categorySnapshotRawValue == template.categoryRawValue)
        #expect(row.timePeriodSnapshotRawValue == template.timePeriodRawValue)
        #expect(row.verificationTypeSnapshotRawValue == template.verificationTypeRawValue)
        #expect(row.xpRewardSnapshot == template.xpReward && row.coinRewardSnapshot == template.coinReward)
        #expect(row.activeBonusCoinSnapshot == template.activeBonusCoin)
        #expect(row.sourceRevision == 1 && row.plannedAt == plan && row.deadlineAt == deadline)
        #expect(row.updatedAt == now)
    }

    @Test("坏类型、照片验收、负奖励或最大 Coin 溢出在插改删之前拒绝", arguments: Array(0..<8))
    func invalidConfigurationDoesNotPartiallyMutate(field: Int) throws {
        let context = try makeContext()
        let template = makeTemplate()
        context.insert(template)
        let mutable = try occurrence(template: template, dateKey: "2026-09-24", status: .pending)
        let removable = try occurrence(template: template, dateKey: "2026-09-25", status: .pending)
        context.insert(mutable)
        context.insert(removable)
        let originalTime = mutable.scheduledAt
        let originalUpdatedAt = mutable.updatedAt
        template.title = "不可传播的新标题"
        let expected: any Error
        switch field {
        case 0:
            template.categoryRawValue = "corrupt"
            expected = OccurrenceReconciliationError.invalidTemplateConfiguration(
                templateID: template.id, field: "category", rawValue: "corrupt")
        case 1:
            template.timePeriodRawValue = "corrupt"
            expected = OccurrenceReconciliationError.invalidTemplateConfiguration(
                templateID: template.id, field: "timePeriod", rawValue: "corrupt")
        case 2, 3:
            template.verificationTypeRawValue = field == 2 ? "corrupt" : "photoRecord"
            expected = OccurrenceReconciliationError.invalidTemplateConfiguration(
                templateID: template.id, field: "verificationType", rawValue: template.verificationTypeRawValue)
        case 4: template.xpReward = -1; expected = RewardLedgerError.invalidAmount
        case 5: template.coinReward = -1; expected = RewardLedgerError.invalidAmount
        case 6: template.activeBonusCoin = -1; expected = RewardLedgerError.invalidAmount
        default:
            template.coinReward = Int.max
            template.activeBonusCoin = 1
            expected = RewardLedgerError.integerOverflow
        }
        try context.save()
        let desired = [
            try candidate("2026-09-24", hour: 20, revision: 1),
            try candidate("2026-09-26", hour: 20, revision: 1),
        ]
        #expect {
            try TaskOccurrenceReconciliationService(context: context).reconcile(
                template: template, candidates: desired,
                in: localDate("2026-09-23")...localDate("2026-09-26"), today: localDate("2026-09-23"),
                now: instant("2026-09-23T04:00:00Z"))
        } throws: { error in
            if let expected = expected as? OccurrenceReconciliationError {
                return (error as? OccurrenceReconciliationError) == expected
            }
            return (error as? RewardLedgerError) == (expected as? RewardLedgerError)
        }
        #expect(Set(try fetchOccurrences(context).map(\.id)) == [mutable.id, removable.id])
        #expect(mutable.titleSnapshot == "阅读" && mutable.scheduledAt == originalTime)
        #expect(mutable.updatedAt == originalUpdatedAt && !context.hasChanges)
        expectConfiguration(mutable, category: .unassigned, period: .allDay, verification: .selfConfirm, reward: 0)
    }

    @Test("最大有效显式金额不被截断且零旧配置保持兼容")
    func acceptsSafeIntegerBoundaryAndLegacyZero() throws {
        let context = try makeContext()
        let template = makeTemplate()
        template.xpReward = Int.max
        template.coinReward = Int.max - 1
        template.activeBonusCoin = 1
        context.insert(template)
        try context.save()
        let date = try localDate("2026-09-23")
        let service = TaskOccurrenceReconciliationService(context: context)
        _ = try service.reconcile(
            template: template, candidates: [candidate(date.dateKey, hour: 19, revision: 1)], in: date...date,
            today: date, now: instant("2026-09-23T01:00:00Z"))
        let row = try #require(fetchOccurrences(context).first)
        #expect(
            row.xpRewardSnapshot == Int.max && row.coinRewardSnapshot == Int.max - 1 && row.activeBonusCoinSnapshot == 1
        )
        template.xpReward = 0
        template.coinReward = 0
        template.activeBonusCoin = 0
        try context.save()
        _ = try service.reconcile(
            template: template, candidates: [candidate(date.dateKey, hour: 19, revision: 1)], in: date...date,
            today: date, now: instant("2026-09-23T02:00:00Z"))
        expectConfiguration(row, category: .unassigned, period: .allDay, verification: .selfConfirm, reward: 0)
    }

    private func expectConfiguration(
        _ row: TaskOccurrence, category: TaskCategory, period: TaskTimePeriod,
        verification: TaskVerificationType, reward: Int = 11
    ) {
        #expect(row.categorySnapshot == category && row.timePeriodSnapshot == period)
        #expect(row.verificationTypeSnapshot == verification)
        #expect(row.xpRewardSnapshot == reward)
        #expect(row.coinRewardSnapshot == (reward == 0 ? 0 : 7))
        #expect(row.activeBonusCoinSnapshot == (reward == 0 ? 0 : 3))
    }

    @Test("正式模板物化、配置更新与等待保护经过两次磁盘重开仍一致")
    func materializedConfigurationSurvivesDiskReopen() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let ids = try seedConfiguredDisk(at: url)
        try updateConfiguredDisk(at: url, waitingID: ids.waiting)
        for _ in 0..<2 {
            let context = ModelContext(try AppModelContainer.make(storeURL: url))
            context.autosaveEnabled = false
            let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
            let rows = try fetchOccurrences(context)
            #expect(Set(rows.map(\.id)) == ids.all)
            let waiting = try #require(rows.first { $0.id == ids.waiting })
            expectConfiguration(waiting, category: .growth, period: .morning, verification: .parentApproval)
            #expect(waiting.sourceRevision == 1)
            for row in rows where row.id != ids.waiting {
                #expect(row.categorySnapshot == .challenge && row.timePeriodSnapshot == .evening)
                #expect(row.verificationTypeSnapshot == .selfConfirm)
                #expect(row.xpRewardSnapshot == 41 && row.coinRewardSnapshot == 23 && row.activeBonusCoinSnapshot == 9)
                #expect(row.sourceRevision == 2 && row.plannedAt == nil && row.deadlineAt == nil)
            }
            let submission = try #require(context.fetch(FetchDescriptor<TaskSubmission>()).first)
            #expect(submission.occurrenceID == ids.waiting && submission.reviewState == .waiting)
            #expect(
                submission.xpRewardSnapshot == 11 && submission.coinRewardSnapshot == 7
                    && submission.activeBonusCoinSnapshot == 3)
            #expect(try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
            let report = try materializer(context).reconcile(
                template: template, today: localDate("2026-09-23"), now: instant("2026-09-23T03:00:00Z"))
            #expect(report == .init(insertedCount: 0, updatedCount: 0, deletedCount: 0, protectedCount: 1))
            #expect(!context.hasChanges)
        }
    }

    /// 每一阶段只传稳定 ID，确保重新打开时不复用上一容器的模型对象。
    private func seedConfiguredDisk(at url: URL) throws -> (waiting: UUID, all: Set<UUID>) {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let template = makeTemplate()
        template.categoryRawValue = TaskCategory.growth.rawValue
        template.timePeriodRawValue = TaskTimePeriod.morning.rawValue
        template.verificationTypeRawValue = TaskVerificationType.parentApproval.rawValue
        template.xpReward = 11
        template.coinReward = 7
        template.activeBonusCoin = 3
        let today = try localDate("2026-09-23")
        let rule = ReminderRule(
            taskTemplateID: template.id,
            recurrence: try .weekly(on: Set(Weekday.allCases), starting: today), timeOfDayMinutes: 19 * 60)
        context.insert(template)
        context.insert(rule)
        template.reminderRule = rule
        rule.taskTemplate = template
        try context.save()
        // 首次正式物化保证今天可用；再以同一规则扩展已物化范围，模拟通知滚动排程。
        _ = try materializer(context).reconcile(template: template, today: today, now: instant("2026-09-23T01:00:00Z"))
        _ = try TaskOccurrenceReconciliationService(context: context).reconcile(
            template: template,
            candidates: [
                candidate("2026-09-23", hour: 19, revision: 1), candidate("2026-09-24", hour: 19, revision: 1),
                candidate("2026-09-25", hour: 19, revision: 1),
            ],
            in: today...localDate("2026-09-25"), today: today, now: instant("2026-09-23T01:00:00Z"))
        let rows = try fetchOccurrences(context)
        let waiting = try #require(rows.first { $0.dateKey == today.dateKey })
        expectConfiguration(waiting, category: .growth, period: .morning, verification: .parentApproval)
        _ = try TaskSubmissionService(context: context).submit(waiting, at: instant("2026-09-23T01:30:00Z"))
        return (waiting.id, Set(rows.map(\.id)))
    }

    private func updateConfiguredDisk(at url: URL, waitingID: UUID) throws {
        let context = ModelContext(try AppModelContainer.make(storeURL: url))
        context.autosaveEnabled = false
        let template = try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first)
        template.categoryRawValue = TaskCategory.challenge.rawValue
        template.timePeriodRawValue = TaskTimePeriod.evening.rawValue
        template.verificationTypeRawValue = TaskVerificationType.selfConfirm.rawValue
        template.xpReward = 41
        template.coinReward = 23
        template.activeBonusCoin = 9
        template.revision = 2
        try context.save()
        let report = try materializer(context).reconcile(
            template: template, today: localDate("2026-09-23"), now: instant("2026-09-23T02:00:00Z"))
        #expect(report.updatedCount == 2 && report.protectedCount == 1)
        let waiting = try #require(fetchOccurrences(context).first { $0.id == waitingID })
        expectConfiguration(waiting, category: .growth, period: .morning, verification: .parentApproval)
    }

    private func materializer(_ context: ModelContext) throws -> TaskOccurrenceMaterializationService {
        TaskOccurrenceMaterializationService(
            context: context, calendar: .init(identifier: .gregorian),
            timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")))
    }

    private func makeContext() throws -> ModelContext {
        let context = try ModelContext(AppModelContainer.make(inMemory: true))
        context.autosaveEnabled = false
        return context
    }

    private func makeTemplate() -> TaskTemplate {
        TaskTemplate(
            title: "阅读",
            iconName: "book.fill",
            colorToken: "reading",
            targetDurationSeconds: 900,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private func occurrence(
        template: TaskTemplate,
        dateKey: String,
        status: TaskOccurrenceStatus,
        detached: Bool = false
    ) throws -> TaskOccurrence {
        let date = try localDate(dateKey)
        let occurrence = TaskOccurrence(
            templateID: template.id,
            date: date,
            scheduledAt: try scheduledAt(dateKey, hour: 19),
            titleSnapshot: template.title,
            iconSnapshot: template.iconName,
            colorSnapshot: template.colorToken,
            targetDurationSnapshot: template.targetDurationSeconds,
            status: status,
            sourceRevision: template.revision,
            isDetachedOverride: detached,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
        occurrence.template = template
        return occurrence
    }

    private func candidate(
        _ dateKey: String,
        hour: Int,
        revision: Int
    ) throws -> ResolvedTaskCandidate {
        .init(
            date: try localDate(dateKey),
            scheduledAt: try scheduledAt(dateKey, hour: hour),
            origin: .generated(templateRevision: revision)
        )
    }

    private func scheduledAt(_ dateKey: String, hour: Int) throws -> Date {
        let date = try localDate(dateKey)
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        return try #require(
            TaskRecurrenceExpander(calendar: .init(identifier: .gregorian), timeZone: timeZone)
                .expand(
                    .once(on: date),
                    timeOfDayMinutes: hour * 60,
                    from: date,
                    through: date
                ).first?.scheduledAt
        )
    }

    private func fetchOccurrences(_ context: ModelContext) throws -> [TaskOccurrence] {
        try context.fetch(FetchDescriptor<TaskOccurrence>())
    }

    private func localDate(_ dateKey: String) throws -> LocalDate {
        try LocalDate(dateKey: dateKey)
    }

    private func instant(_ value: String) throws -> Date {
        try Date(value, strategy: .iso8601)
    }
}
