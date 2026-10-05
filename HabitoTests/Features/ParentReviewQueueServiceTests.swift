import Foundation
import SwiftData
import Testing
@testable import Habito

@MainActor
@Suite("家长待验收纯值队列")
struct ParentReviewQueueServiceTests {
    @Test("空库和旧零奖励未提交任务不会被猜为待审核")
    func emptyAndLegacyTasksHaveNoReview() throws {
        let fixture = try TodayQueryFixture()
        let query = ParentReviewQueueService(context: fixture.context)
        #expect(try query.items().isEmpty)
        _ = fixture.makeOccurrence(title: "合成旧任务", scheduledAt: fixture.now, status: .pending)
        try fixture.context.save()
        #expect(try query.items().isEmpty && !fixture.context.hasChanges)
    }

    @Test("跨日过期提交不消失，原时间奖励和时长不受后来配置污染", arguments: [-1.0, 0.0, 1.0])
    func crossDayUsesFrozenSnapshot(offset: TimeInterval) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting(day: "2026-09-20", submittedOffset: 60 + offset)
        occurrence.scheduledAt = fixture.now.addingTimeInterval(-86400)
        occurrence.xpRewardSnapshot = 999
        occurrence.coinRewardSnapshot = 999
        occurrence.activeBonusCoinSnapshot = 999
        occurrence.verificationTypeSnapshotRawValue = TaskVerificationType.selfConfirm.rawValue
        try fixture.context.save()
        let original = try fixture.item(for: occurrence)
        #expect(original.taskDate == (try LocalDate(dateKey: "2026-09-20")))
        #expect(original.submittedAt == fixture.now.addingTimeInterval(60 + offset))
        #expect(original.reminderAt == fixture.now.addingTimeInterval(60) && original.expectedXP == 11)
        #expect(original.expectedBaseCoins == 7 && original.expectedAutonomyCoins == (offset < 0 ? 3 : 0))
        #expect(original.expectedCoins == (offset < 0 ? 10 : 7))
        #expect(original.timing == (offset < 0 ? .beforeReminder : .afterReminder))
        #expect(original.activeDurationSeconds == 90 + offset)
        for _ in 0..<5 { #expect(try fixture.item(for: occurrence) == original) }
        #expect(!fixture.context.hasChanges)
        try fixture.expectNoReward()
    }

    @Test("排序最早提交优先，同刻按所属日期与稳定提交 ID，查询不写数据")
    func stableOrderDoesNotMutateStore() throws {
        let fixture = try ParentReviewFixture()
        let inputs = [
            (V0MigrationFixture.pendingID, V0MigrationFixture.completedID, "2026-09-23", 0.0),
            (V0MigrationFixture.activeID, V0MigrationFixture.orphanID, "2026-09-22", 0.0),
            (V0MigrationFixture.completedID, V0MigrationFixture.pendingID, "2026-09-23", -1.0),
            (V0MigrationFixture.orphanID, V0MigrationFixture.activeID, "2026-09-23", 0.0),
        ]
        for (occurrenceID, submissionID, day, offset) in inputs {
            // 同日同模板只允许一个实例；排序夹具必须使用不同模板键，避免唯一约束合并数据。
            let occurrence = TaskOccurrence(
                id: occurrenceID, templateID: occurrenceID,
                date: try LocalDate(dateKey: day), scheduledAt: fixture.now,
                titleSnapshot: "合成排序", iconSnapshot: "book.fill", colorSnapshot: "reading",
                targetDurationSnapshot: 900, sourceRevision: 1, createdAt: fixture.now, updatedAt: fixture.now)
            fixture.context.insert(occurrence)
            let snapshot = try CompletionRewardSnapshot(
                submittedAt: fixture.now.addingTimeInterval(offset), reminderAt: fixture.now,
                xp: 0, baseCoins: 0, autonomyBonusCoins: 0)
            fixture.context.insert(
                TaskSubmission(
                    id: submissionID, occurrenceID: occurrenceID, sequenceNumber: 1,
                    snapshot: snapshot, activeDurationSeconds: 0))
        }
        try fixture.context.save()
        let expected =
            [inputs[2].1, inputs[1].1] + [inputs[0].1, inputs[3].1].sorted { $0.uuidString < $1.uuidString }
        for _ in 0..<5 {
            #expect(try ParentReviewQueueService(context: fixture.context).items().map(\.id) == expected)
        }
        #expect(!fixture.context.hasChanges)
        try fixture.expectNoReward()
    }

    @Test("通过和退回不在等待队列，退回后同刻重提只出现新轮次", arguments: [false, true])
    func reviewedRowsAndSameTimeResubmission(approve: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let first = try fixture.item(for: occurrence)
        let review = TaskSubmissionReviewService(context: fixture.context)
        if approve {
            _ = try review.approve(occurrence, submissionID: first.id, at: fixture.now)
        } else {
            _ = try review.returnForRevision(occurrence, submissionID: first.id, at: fixture.now)
        }
        #expect(try ParentReviewQueueService(context: fixture.context).items().isEmpty)
        if !approve {
            let next = try TaskSubmissionService(context: fixture.context).submit(occurrence, at: fixture.now)
            let item = try fixture.item(for: occurrence)
            #expect(item.id == next.submissionID && item.id != first.id && item.submittedAt == first.submittedAt)
            #expect(item.activeDurationSeconds == 30)
            try fixture.expectNoReward()
        }
    }

    @Test("损坏状态计时或元数据必须失败，不能伪装成空队列", arguments: [0, 1, 2, 3])
    func damagedWaitingIsExplicitFailure(kind: Int) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let row = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
        switch kind {
        case 0: row.reviewStateRawValue = "synthetic-invalid"
        case 1: occurrence.statusRawValue = TaskOccurrenceStatus.skipped.rawValue
        case 2: try #require(occurrence.timerSessions.first).accumulatedActiveSeconds += 1
        default: row.reviewedCompletionID = V0MigrationFixture.orphanID
        }
        try fixture.context.save()
        #expect(throws: (any Error).self) { try ParentReviewQueueService(context: fixture.context).items() }
        #expect(!fixture.context.hasChanges)
        try fixture.expectNoReward()
    }

    @Test("孤儿审计显式拒绝，不因没有实例而静默丢弃")
    func orphanAuditCannotDisappear() throws {
        let fixture = try ParentReviewFixture()
        let snapshot = try CompletionRewardSnapshot(
            submittedAt: fixture.now, reminderAt: fixture.now, xp: 0, baseCoins: 0, autonomyBonusCoins: 0)
        fixture.context.insert(
            TaskSubmission(
                occurrenceID: V0MigrationFixture.orphanID, sequenceNumber: 1, snapshot: snapshot,
                activeDurationSeconds: 0))
        try fixture.context.save()
        #expect(throws: ParentReviewQueueError.occurrenceNotFound(V0MigrationFixture.orphanID)) {
            try ParentReviewQueueService(context: fixture.context).items()
        }
    }
}
