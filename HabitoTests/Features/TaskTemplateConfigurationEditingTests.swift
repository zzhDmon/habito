import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("模板显式配置编辑与原子保存")
struct TaskTemplateConfigurationEditingTests {
    @Test("新建和原样重存两种验收与零/显式奖励，改旧字段不抹 V1", arguments: TaskVerificationType.allCases, [false, true])
    func createsReloadsAndKeepsConfiguration(verification: TaskVerificationType, zero: Bool) throws {
        let fixture = try Fixture()
        var draft = configuredDraft(verification: verification, zero: zero)
        let id = try fixture.service.save(draft, at: fixture.now)
        draft = try fixture.service.load(templateID: id)
        #expect(
            draft.category == .challenge && draft.timePeriod == .afterSchool && draft.verificationType == verification)
        #expect(
            draft.xpReward == (zero ? 0 : 11) && draft.coinReward == (zero ? 0 : 7)
                && draft.activeBonusCoin == (zero ? 0 : 3))
        #expect(try fixture.service.save(draft, at: fixture.now.addingTimeInterval(1)) == id)
        draft.title = "只改旧标题"
        _ = try fixture.service.save(draft, at: fixture.now.addingTimeInterval(2))
        let reloaded = try fixture.service.load(templateID: id)
        #expect(reloaded == draft)
        let row = try fixture.occurrence()
        #expect(row.categorySnapshot == .challenge && row.timePeriodSnapshot == .afterSchool)
        #expect(row.verificationTypeSnapshot == verification)
        #expect(
            row.xpRewardSnapshot == draft.xpReward && row.coinRewardSnapshot == draft.coinReward
                && row.activeBonusCoinSnapshot == draft.activeBonusCoin)
        #expect(row.sourceRevision == 3 && row.plannedAt == nil && row.deadlineAt == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("负奖励和加总溢出在创建任何模型前拒绝", arguments: Array(0..<4))
    func rejectsInvalidRewardBeforeCreate(field: Int) throws {
        let fixture = try Fixture()
        var draft = configuredDraft()
        switch field {
        case 0: draft.xpReward = -1
        case 1: draft.coinReward = -1
        case 2: draft.activeBonusCoin = -1
        default: draft.coinReward = Int.max; draft.activeBonusCoin = 1
        }
        #expect(throws: field == 3 ? TaskTemplateEditorError.rewardOverflow : .invalidReward) {
            try fixture.service.save(draft, at: fixture.now)
        }
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<ReminderRule>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("安全最大金额原样保存，模板最大修订号只读可载入但编辑拒绝")
    func preservesIntegerBoundaryAndRejectsRevisionOverflow() throws {
        let fixture = try Fixture()
        var draft = configuredDraft()
        draft.xpReward = Int.max
        draft.coinReward = Int.max - 1
        draft.activeBonusCoin = 1
        let id = try fixture.service.save(draft, at: fixture.now)
        let template = try fixture.template()
        template.revision = Int.max
        try fixture.context.save()
        var loaded = try fixture.service.load(templateID: id)
        #expect(loaded.xpReward == Int.max && loaded.coinReward == Int.max - 1 && loaded.activeBonusCoin == 1)
        loaded.title = "不可保存"
        #expect(throws: TaskTemplateEditorError.revisionOverflow) {
            try fixture.service.save(loaded, at: fixture.now.addingTimeInterval(1))
        }
        #expect(template.title == "显式合成配置" && template.revision == Int.max)
        #expect(try fixture.occurrence().sourceRevision == 1 && !fixture.context.hasChanges)
    }

    @Test("坏存储类型/照片/奖励/修订/时长不可载入或被草稿洗白", arguments: Array(0..<12))
    func rejectsCorruptStoredConfiguration(field: Int) throws {
        let fixture = try Fixture()
        let id = try fixture.service.save(configuredDraft(), at: fixture.now)
        let template = try fixture.template()
        let validDraft = try fixture.service.load(templateID: id)
        switch field {
        case 0: template.categoryRawValue = "corrupt"
        case 1: template.timePeriodRawValue = "corrupt"
        case 2: template.verificationTypeRawValue = "corrupt"
        case 3: template.verificationTypeRawValue = "photoRecord"
        case 4: template.xpReward = -1
        case 5: template.coinReward = -1
        case 6: template.activeBonusCoin = -1
        case 7: template.coinReward = Int.max; template.activeBonusCoin = 1
        case 8: template.revision = 0
        case 9: template.targetDurationSeconds = .infinity
        case 10: template.targetDurationSeconds = -1
        default: template.targetDurationSeconds = 180 * 60 + 1
        }
        try fixture.context.save()
        #expect(throws: (any Error).self) { try fixture.service.load(templateID: id) }
        #expect(throws: (any Error).self) {
            try fixture.service.save(validDraft, at: fixture.now.addingTimeInterval(1))
        }
        let row = try fixture.occurrence()
        #expect(row.titleSnapshot == "显式合成配置" && row.xpRewardSnapshot == 11 && row.sourceRevision == 1)
        #expect(template.title == "显式合成配置" && !fixture.context.hasChanges)
    }

    @Test("已有脏编辑被拒绝，不保存也不回滚其他用户输入", arguments: [false, true])
    func preservesPendingUserChanges(creating: Bool) throws {
        let fixture = try Fixture()
        let id = try fixture.service.save(configuredDraft(), at: fixture.now)
        let template = try fixture.template()
        var draft = creating ? configuredDraft() : try fixture.service.load(templateID: id)
        draft.title = "本次不能保存"
        template.title = "其他页面未保存的输入"
        var saves = 0
        let service = fixture.makeService { context in
            saves += 1; try context.save()
        }
        #expect(throws: TaskTemplateEditorError.pendingContextChanges) { try service.save(draft, at: fixture.now) }
        #expect(saves == 0 && fixture.context.hasChanges)
        #expect(template.title == "其他页面未保存的输入")
        #expect(try fixture.occurrence().titleSnapshot == "显式合成配置")
    }

    @Test("新建保存失败清除本次新图，自动保存恢复且可正常重试")
    func failedCreateHasNoPartialModelAndCanRetry() throws {
        let fixture = try Fixture()
        fixture.context.autosaveEnabled = true
        var attempts = 0
        let failing = fixture.makeService { context in
            #expect(!context.autosaveEnabled)
            attempts += 1
            throw saveFailure
        }
        #expect(throws: saveFailure) { try failing.save(configuredDraft(), at: fixture.now) }
        #expect(attempts == 1 && fixture.context.autosaveEnabled && !fixture.context.hasChanges)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<ReminderRule>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
        _ = try fixture.service.save(configuredDraft(), at: fixture.now)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 1)
    }

    @Test("编辑更新或清理实例后保存失败恢复全部配置与拥有关系", arguments: [false, true])
    func failedEditRestoresUpdatedOrDeletedGraph(removing: Bool) throws {
        let fixture = try Fixture()
        let id = try fixture.service.save(configuredDraft(), at: fixture.now)
        let original = try fixture.service.load(templateID: id)
        let occurrence = try fixture.occurrence()
        let occurrenceID = occurrence.id
        let originalScheduledAt = occurrence.scheduledAt
        let session = TimerSession(
            occurrenceID: occurrenceID, state: .ended, startedAt: fixture.now, lastResumedAt: fixture.now,
            accumulatedActiveSeconds: 12, endedAt: fixture.now.addingTimeInterval(12))
        let link = NotificationLink(
            requestIdentifier: NotificationRequestIdentifier(occurrenceID: occurrenceID, kind: .primary).rawValue,
            occurrenceID: occurrenceID, kind: .primary, scheduledAt: originalScheduledAt, createdAt: fixture.now)
        fixture.context.insert(session)
        fixture.context.insert(link)
        session.occurrence = occurrence
        link.occurrence = occurrence
        try fixture.context.save()
        fixture.context.autosaveEnabled = true
        var changed = original
        changed.title = "失败的新标题"
        changed.timeOfDayMinutes = 20 * 60
        changed.targetDurationMinutes = 30
        changed.category = .growth
        changed.timePeriod = .evening
        changed.verificationType = .selfConfirm
        changed.xpReward = 41
        changed.coinReward = 23
        changed.activeBonusCoin = 9
        if removing { changed.weekdays = [.monday] }
        var attempts = 0
        let failing = fixture.makeService { context in
            #expect(!context.autosaveEnabled)
            attempts += 1
            throw saveFailure
        }
        #expect(throws: saveFailure) { try failing.save(changed, at: fixture.now.addingTimeInterval(60)) }
        #expect(attempts == 1 && !fixture.context.hasChanges && fixture.context.autosaveEnabled)
        #expect(try fixture.service.load(templateID: id) == original)
        let restored = try fixture.occurrence()
        #expect(restored.id == occurrenceID && restored.titleSnapshot == "显式合成配置" && restored.sourceRevision == 1)
        #expect(restored.scheduledAt == originalScheduledAt && restored.updatedAt == fixture.now)
        #expect(
            restored.categorySnapshot == .challenge && restored.timePeriodSnapshot == .afterSchool
                && restored.verificationTypeSnapshot == .parentApproval)
        #expect(
            restored.xpRewardSnapshot == 11 && restored.coinRewardSnapshot == 7 && restored.activeBonusCoinSnapshot == 3
        )
        #expect(restored.template?.id == id)
        #expect(session.occurrence?.id == occurrenceID)
        #expect(link.occurrence?.id == occurrenceID)
        #expect(restored.timerSessions.map(\.id) == [session.id])
        #expect(restored.notificationLinks.map(\.id) == [link.id])
        #expect(try fixture.context.fetchCount(FetchDescriptor<TimerSession>()) == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<NotificationLink>()) == 1)
    }

    @Test("坏实例阻止编辑物化，模板/规则也恢复而不是半保存")
    func materializationFailureRestoresTemplateAndRule() throws {
        let fixture = try Fixture()
        let id = try fixture.service.save(configuredDraft(), at: fixture.now)
        let original = try fixture.service.load(templateID: id)
        let row = try fixture.occurrence()
        row.statusRawValue = "corrupt"
        try fixture.context.save()
        var changed = original
        changed.title = "不能传播"
        changed.xpReward = 41
        changed.timeOfDayMinutes = 20 * 60
        #expect(throws: OccurrenceReconciliationError.invalidStoredStatus(occurrenceID: row.id, rawValue: "corrupt")) {
            try fixture.service.save(changed, at: fixture.now.addingTimeInterval(1))
        }
        #expect(try fixture.service.load(templateID: id) == original)
        #expect(try fixture.template().revision == 1 && row.statusRawValue == "corrupt" && !fixture.context.hasChanges)
    }

    @Test("旧冻结 V0 磁盘模板载入零/待设置/全天并可编辑，不补历史奖励")
    func readsAndEditsMigratedLegacyStoreWithoutInventingConfiguration() throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        try V0MigrationFixture.seed(at: url)
        try editLegacyStore(at: url)
        for _ in 0..<2 {
            let fixture = try Fixture(storeURL: url)
            let draft = try fixture.service.load(templateID: V0MigrationFixture.templateID)
            #expect(draft.title == "只改迁移后标题")
            #expect(
                draft.category == .unassigned && draft.timePeriod == .allDay && draft.verificationType == .selfConfirm)
            #expect(draft.xpReward == 0 && draft.coinReward == 0 && draft.activeBonusCoin == 0)
            #expect(try fixture.context.fetchCount(FetchDescriptor<XPTransaction>()) == 0)
            #expect(try fixture.context.fetchCount(FetchDescriptor<CoinTransaction>()) == 0)
        }
    }

    private func editLegacyStore(at url: URL) throws {
        let fixture = try Fixture(storeURL: url)
        var draft = try fixture.service.load(templateID: V0MigrationFixture.templateID)
        draft.title = "只改迁移后标题"
        _ = try fixture.service.save(draft, at: fixture.now)
    }

    @Test("显式配置编辑经过等待/退回/冲正保护与两次磁盘重开保持原快照", arguments: Array(0..<3))
    func configuredEditingKeepsAuditedSnapshotAcrossReopen(outcome: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let ids = try seedAuditedConfiguration(at: url, outcome: outcome)
        for _ in 0..<2 {
            let fixture = try Fixture(storeURL: url)
            let draft = try fixture.service.load(templateID: ids.template)
            #expect(draft.title == "磁盘新版" && draft.category == .growth && draft.timePeriod == .evening)
            #expect(
                draft.verificationType == .selfConfirm && draft.xpReward == 41 && draft.coinReward == 23
                    && draft.activeBonusCoin == 9)
            let rows = try fixture.context.fetch(FetchDescriptor<TaskOccurrence>())
            let audited = try #require(rows.first { $0.id == ids.audited })
            let ordinary = try #require(rows.first { $0.id != ids.audited })
            #expect(rows.count == 2 && audited.sourceRevision == 1 && ordinary.sourceRevision == 2)
            #expect(audited.categorySnapshot == .challenge && audited.timePeriodSnapshot == .afterSchool)
            #expect(audited.verificationTypeSnapshot == .parentApproval)
            #expect(
                audited.xpRewardSnapshot == 11 && audited.coinRewardSnapshot == 7
                    && audited.activeBonusCoinSnapshot == 3)
            #expect(ordinary.categorySnapshot == .growth && ordinary.timePeriodSnapshot == .evening)
            #expect(ordinary.verificationTypeSnapshot == .selfConfirm && ordinary.xpRewardSnapshot == 41)
            #expect(ordinary.coinRewardSnapshot == 23 && ordinary.activeBonusCoinSnapshot == 9)
            let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
            #expect(
                row.id == ids.submission && row.xpRewardSnapshot == 11 && row.coinRewardSnapshot == 7
                    && row.activeBonusCoinSnapshot == 3)
            #expect(row.reviewState == (outcome == 0 ? .waiting : outcome == 1 ? .returned : .approved))
            if outcome == 2 {
                let completion = try #require(fixture.context.fetch(FetchDescriptor<CompletionRecord>()).first)
                #expect(completion.revokedAt != nil && completion.occurrence == nil && audited.completionRecord == nil)
            }
            #expect(try RewardLedgerService(context: fixture.context).balance() == .init(effectiveXP: 0, coins: 0))
            #expect(!fixture.context.hasChanges)
        }
    }

    /// 每阶段只返回稳定 ID，不能跨容器复用模型；实际保存而不是拼接快照冒充编辑。
    private func seedAuditedConfiguration(at url: URL, outcome: Int) throws -> (
        template: UUID, audited: UUID, submission: UUID
    ) {
        let fixture = try Fixture(storeURL: url)
        let id = try fixture.service.save(configuredDraft(), at: fixture.now)
        let template = try fixture.template()
        let today = try V0MigrationFixture.date("2026-09-23")
        let tomorrow = try V0MigrationFixture.date("2026-09-24")
        _ = try TaskOccurrenceReconciliationService(context: fixture.context).reconcile(
            template: template,
            candidates: [
                .init(
                    date: today, scheduledAt: try fixture.occurrence().scheduledAt,
                    origin: .generated(templateRevision: 1)),
                .init(
                    date: tomorrow, scheduledAt: fixture.now.addingTimeInterval(86_400 + 27_000),
                    origin: .generated(templateRevision: 1)),
            ], in: today...tomorrow, today: today, now: fixture.now)
        let audited = try #require(
            fixture.context.fetch(FetchDescriptor<TaskOccurrence>()).first { $0.dateKey == today.dateKey })
        let submitted = try TaskSubmissionService(context: fixture.context).submit(audited, at: fixture.now)
        if outcome == 1 {
            _ = try TaskSubmissionReviewService(context: fixture.context).returnForRevision(
                audited, submissionID: submitted.submissionID, at: fixture.now.addingTimeInterval(1))
        } else if outcome == 2 {
            let result = try TaskSubmissionReviewService(context: fixture.context).approve(
                audited, submissionID: submitted.submissionID, at: fixture.now.addingTimeInterval(1))
            _ = try TaskCompletionUndoService(context: fixture.context).undo(
                audited, completionID: #require(result.completionID), at: fixture.now.addingTimeInterval(2))
        }
        var changed = try fixture.service.load(templateID: id)
        changed.title = "磁盘新版"
        changed.category = .growth
        changed.timePeriod = .evening
        changed.verificationType = .selfConfirm
        changed.xpReward = 41
        changed.coinReward = 23
        changed.activeBonusCoin = 9
        _ = try fixture.service.save(changed, at: fixture.now.addingTimeInterval(3))
        // 即使此次编辑只会触及普通未来实例，失败恢复也不能把冲正记录挂成当前完成。
        var failed = changed
        failed.title = "不能半保存"
        failed.xpReward = 99
        let failing = fixture.makeService { _ in throw saveFailure }
        #expect(throws: saveFailure) { try failing.save(failed, at: fixture.now.addingTimeInterval(4)) }
        #expect(!fixture.context.hasChanges && audited.completionRecord == nil)
        return (id, audited.id, submitted.submissionID)
    }

    @Test("磁盘新建/更新/删除图保存失败后两次重开无半写入", arguments: Array(0..<3))
    func failedDiskTransactionLeavesOriginalStore(kind: Int) throws {
        let url = try V0MigrationFixture.temporaryStoreURL()
        let expectedID = try performFailedDiskEdit(at: url, kind: kind)
        for _ in 0..<2 {
            let fixture = try Fixture(storeURL: url)
            if let expectedID {
                let loaded = try fixture.service.load(templateID: expectedID)
                #expect(loaded.title == "显式合成配置" && loaded.category == .challenge && loaded.timePeriod == .afterSchool)
                #expect(
                    loaded.verificationType == .parentApproval && loaded.xpReward == 11 && loaded.coinReward == 7
                        && loaded.activeBonusCoin == 3)
                let row = try fixture.occurrence()
                #expect(row.sourceRevision == 1 && row.template?.id == expectedID)
                #expect(
                    row.categorySnapshot == .challenge && row.timePeriodSnapshot == .afterSchool
                        && row.verificationTypeSnapshot == .parentApproval)
                #expect(row.xpRewardSnapshot == 11 && row.coinRewardSnapshot == 7 && row.activeBonusCoinSnapshot == 3)
                #expect(row.timerSessions.count == 1 && row.notificationLinks.count == 1)
                #expect(
                    row.timerSessions.first?.occurrence?.id == row.id
                        && row.notificationLinks.first?.occurrence?.id == row.id)
            } else {
                #expect(try fixture.context.fetchCount(FetchDescriptor<TaskTemplate>()) == 0)
                #expect(try fixture.context.fetchCount(FetchDescriptor<ReminderRule>()) == 0)
                #expect(try fixture.context.fetchCount(FetchDescriptor<TaskOccurrence>()) == 0)
            }
            #expect(!fixture.context.hasChanges)
        }
    }

    private func performFailedDiskEdit(at url: URL, kind: Int) throws -> UUID? {
        let fixture = try Fixture(storeURL: url)
        var draft = configuredDraft()
        var originalID: UUID?
        if kind != 0 {
            let id = try fixture.service.save(draft, at: fixture.now)
            originalID = id
            draft = try fixture.service.load(templateID: id)
            let row = try fixture.occurrence()
            let session = TimerSession(
                occurrenceID: row.id, state: .ended, startedAt: fixture.now, lastResumedAt: fixture.now,
                accumulatedActiveSeconds: 12, endedAt: fixture.now.addingTimeInterval(12))
            let link = NotificationLink(
                requestIdentifier: NotificationRequestIdentifier(occurrenceID: row.id, kind: .primary).rawValue,
                occurrenceID: row.id, kind: .primary, scheduledAt: row.scheduledAt, createdAt: fixture.now)
            fixture.context.insert(session)
            fixture.context.insert(link)
            session.occurrence = row
            link.occurrence = row
            try fixture.context.save()
            draft.title = "磁盘失败输入"
            draft.xpReward = 41
            draft.coinReward = 23
            draft.activeBonusCoin = 9
            draft.category = .growth
            draft.timePeriod = .evening
            if kind == 2 { draft.weekdays = [.monday] }
        }
        let failing = fixture.makeService { _ in throw saveFailure }
        #expect(throws: saveFailure) { try failing.save(draft, at: fixture.now.addingTimeInterval(60)) }
        #expect(!fixture.context.hasChanges)
        if kind != 0 { #expect(try fixture.occurrence().template?.id == originalID) }
        return originalID
    }

    private var saveFailure: NSError { NSError(domain: "HabitoConfigurationEditingTests", code: 1) }

    private func configuredDraft(verification: TaskVerificationType = .parentApproval, zero: Bool = false)
        -> TaskTemplateDraft
    {
        var draft = TaskTemplateDraft.new
        draft.title = "显式合成配置"
        draft.category = .challenge
        draft.timePeriod = .afterSchool
        draft.verificationType = verification
        draft.xpReward = zero ? 0 : 11
        draft.coinReward = zero ? 0 : 7
        draft.activeBonusCoin = zero ? 0 : 3
        return draft
    }

    private final class Fixture {
        let context: ModelContext
        let now: Date
        let calendar = Calendar(identifier: .gregorian)
        let timeZone: TimeZone
        var service: TaskTemplateEditingService { makeService() }

        init(storeURL: URL? = nil) throws {
            context = ModelContext(
                try storeURL.map { try AppModelContainer.make(storeURL: $0) } ?? AppModelContainer.make(inMemory: true))
            context.autosaveEnabled = false
            now = try V0MigrationFixture.instant("2026-09-23T04:00:00Z")
            timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        }

        func makeService(save: @escaping (ModelContext) throws -> Void = { try $0.save() })
            -> TaskTemplateEditingService
        {
            TaskTemplateEditingService(context: context, calendar: calendar, timeZone: timeZone, saveChanges: save)
        }

        func template() throws -> TaskTemplate { try #require(context.fetch(FetchDescriptor<TaskTemplate>()).first) }
        func occurrence() throws -> TaskOccurrence {
            try #require(context.fetch(FetchDescriptor<TaskOccurrence>()).first)
        }
    }
}
