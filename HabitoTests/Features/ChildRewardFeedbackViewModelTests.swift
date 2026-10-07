import Foundation
import SwiftData
import Testing
@testable import Habito

/// 页面生命周期用真实合成服务和固定时钟验证，不依赖 UI 等待或正式家庭库。
@MainActor
struct ChildRewardFeedbackViewModelTests {
    @Test("保存失败替身只在显式隔离启动启用", arguments: [false, true], [false, true])
    func failureInjectionRequiresExplicitTestMode(testMode: Bool, fail: Bool) throws {
        let fixture = try ParentReviewFixture()
        let result = try approve(fixture.makeWaiting(), fixture: fixture)
        let arguments =
            (testMode ? [UITestLaunchConfiguration.enableArgument] : [])
            + (fail ? [UITestChildReceiptServiceFactory.failureArgument] : [])
        let model = makeModel(
            fixture, service: UITestChildReceiptServiceFactory.make(context: fixture.context, arguments: arguments))
        model.load()
        model.acknowledge(completionID: result)
        #expect(model.acknowledgementFailed == (testMode && fail))
        #expect((model.state == .idle) == !(testMode && fail))
        #expect(!fixture.context.hasChanges)
    }

    @Test("普通自主零奖励只展示审核已保存金额，刷新不确认", arguments: [-1.0, 0.0, 1.0], [false, true])
    func approvedFeedbackUsesValidatedSnapshot(offset: TimeInterval, zero: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting(submittedOffset: 60 + offset, zero: zero)
        let model = makeModel(fixture)
        model.load()
        #expect(model.state == .idle)
        let result = try approve(occurrence, fixture: fixture)
        model.load()
        let receipt = try currentReceipt(model)
        #expect(receipt.id == result)
        let presentation = TaskSessionFeedbackPresentation(receipt: receipt)
        #expect(presentation.id == receipt.id)
        #expect(presentation.tone == (offset < 0 ? .autonomous : .completed))
        #expect(presentation.xp == (zero ? nil : 11))
        #expect(presentation.coins == (zero ? nil : (offset < 0 ? 10 : 7)))
        for _ in 0..<3 { model.load() }
        #expect(model.state == .receipt(receipt))
        #expect(occurrence.completionRecord?.childFeedbackAcknowledgedAt == nil)
        #expect(!fixture.context.hasChanges)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("连续点击捕获原ID只确认一条，跨日下一条不误读")
    func capturedIDCannotAcknowledgeNextReceipt() throws {
        let fixture = try ParentReviewFixture()
        let first = try fixture.makeWaiting(day: "2026-09-21")
        let second = try fixture.makeWaiting(id: UUID(), day: "2026-09-22")
        let firstResult = try approve(first, fixture: fixture)
        let secondResult = try approve(second, fixture: fixture, offset: 1)
        let model = makeModel(fixture)
        model.load()
        #expect(try currentReceipt(model).id == firstResult)
        model.acknowledge(completionID: firstResult)
        #expect(try currentReceipt(model).id == secondResult)
        for _ in 0..<3 { model.acknowledge(completionID: firstResult) }
        #expect(second.completionRecord?.childFeedbackAcknowledgedAt == nil)
        model.acknowledge(completionID: secondResult)
        #expect(model.state == .idle && !model.acknowledgementFailed)
        model.load()
        #expect(model.state == .idle)
        try expectTransactions(fixture.context, count: 2)
    }

    @Test("新到收据不抢当前事件，明示继续后才读下一条")
    func refreshKeepsCurrentReceiptIdentity() throws {
        let fixture = try ParentReviewFixture()
        let first = try fixture.makeWaiting()
        let firstResult = try approve(first, fixture: fixture)
        let model = makeModel(fixture)
        model.load()
        let second = try fixture.makeWaiting(id: UUID(), day: "2026-09-22")
        let secondResult = try approve(second, fixture: fixture, offset: 1)
        model.load()
        #expect(try currentReceipt(model).id == firstResult)
        model.acknowledge(completionID: firstResult)
        #expect(try currentReceipt(model).id == secondResult)
    }

    @Test("确认保存失败保留反馈，刷新不吞错误，重试后不再投递")
    func failedSavePreservesReceiptAndRetry() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let result = try approve(occurrence, fixture: fixture)
        var shouldFail = true
        let service = ChildRewardReceiptService(
            context: fixture.context,
            saveChanges: { context in
                if shouldFail { throw NSError(domain: "HabitoSyntheticFeedbackSave", code: 1) }
                try context.save()
            })
        let model = makeModel(fixture, service: service)
        model.load()
        let original = try currentReceipt(model)
        model.acknowledge(completionID: result)
        #expect(model.state == .receipt(original) && model.acknowledgementFailed)
        #expect(occurrence.completionRecord?.childFeedbackAcknowledgedAt == nil)
        #expect(!fixture.context.hasChanges)
        model.load()
        #expect(model.acknowledgementFailed)
        shouldFail = false
        model.acknowledge(completionID: result)
        #expect(model.state == .idle && !model.acknowledgementFailed)
        let reopenedPage = makeModel(fixture)
        reopenedPage.load()
        #expect(reopenedPage.state == .idle)
        try expectTransactions(fixture.context, count: 1)
    }

    @Test("未保存编辑使读取明确失败，保留编辑，保存后可重试")
    func dirtyContextDoesNotEraseUserEditing() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        _ = try approve(occurrence, fixture: fixture)
        let model = makeModel(fixture)
        model.load()
        occurrence.titleSnapshot = "尚未保存的编辑"
        model.load()
        #expect(model.state == .failed)
        #expect(fixture.context.hasChanges && occurrence.titleSnapshot == "尚未保存的编辑")
        try fixture.context.save()
        model.load()
        #expect(try currentReceipt(model).title == "尚未保存的编辑")
        #expect(occurrence.completionRecord?.childFeedbackAcknowledgedAt == nil)
    }

    @Test("撤销后陈旧确认拒绝并移除庆祝，重读为空而不发奖")
    func revokedReceiptCannotContinueCelebration() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let result = try approve(occurrence, fixture: fixture, offset: -118)
        let model = makeModel(fixture)
        model.load()
        _ = try TaskCompletionUndoService(context: fixture.context).undo(
            occurrence, completionID: result, at: fixture.now.addingTimeInterval(3))
        model.acknowledge(completionID: result)
        #expect(model.state == .failed && !model.acknowledgementFailed)
        model.load()
        #expect(model.state == .idle)
        try expectTransactions(fixture.context, count: 2)
    }

    @Test("时间倒退确认失败但不丢收据，页面不自行修改系统时间")
    func earlierClockDoesNotAcknowledgeReceipt() throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let result = try approve(occurrence, fixture: fixture)
        let model = ChildRewardFeedbackViewModel(
            service: ChildRewardReceiptService(context: fixture.context),
            dateProvider: FixedDateProvider(value: fixture.now.addingTimeInterval(-1)))
        model.load()
        model.acknowledge(completionID: result)
        #expect(model.acknowledgementFailed)
        #expect(try currentReceipt(model).id == result)
        #expect(occurrence.completionRecord?.childFeedbackAcknowledgedAt == nil)
    }

    @Test("展示后审计或账本损坏撤下旧庆祝，拒绝确认，不静默变空", arguments: [false, true])
    func changedAuditCannotKeepOldCelebration(ledger: Bool) throws {
        let fixture = try ParentReviewFixture()
        let occurrence = try fixture.makeWaiting()
        let result = try approve(occurrence, fixture: fixture)
        let model = makeModel(fixture)
        model.load()
        if ledger {
            let coin = try #require(fixture.context.fetch(FetchDescriptor<CoinTransaction>()).first)
            fixture.context.delete(coin)
        } else {
            // 合成库移除审计来源，不放宽生产模型的只读快照 setter 来制造坏数据。
            let submission = try #require(fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first)
            fixture.context.delete(submission)
        }
        try fixture.context.save()
        model.acknowledge(completionID: result)
        #expect(model.state == .failed && !model.acknowledgementFailed)
        #expect(occurrence.completionRecord?.childFeedbackAcknowledgedAt == nil)
        model.load()
        #expect(model.state == .failed)
        #expect(!fixture.context.hasChanges)
    }

    private func makeModel(
        _ fixture: ParentReviewFixture, service: ChildRewardReceiptService? = nil
    ) -> ChildRewardFeedbackViewModel {
        ChildRewardFeedbackViewModel(
            service: service ?? ChildRewardReceiptService(context: fixture.context),
            dateProvider: FixedDateProvider(value: fixture.now.addingTimeInterval(200)))
    }

    private func currentReceipt(_ model: ChildRewardFeedbackViewModel) throws -> ChildRewardReceipt {
        guard case let .receipt(receipt) = model.state else {
            throw NSError(domain: "HabitoSyntheticFeedbackState", code: 1)
        }
        return receipt
    }

    private func approve(
        _ occurrence: TaskOccurrence, fixture: ParentReviewFixture, offset: TimeInterval = 0
    ) throws -> UUID {
        let submission = try #require(
            fixture.context.fetch(FetchDescriptor<TaskSubmission>()).first {
                $0.occurrenceID == occurrence.id && $0.reviewState == .waiting
            })
        let result = try TaskSubmissionReviewService(context: fixture.context).approve(
            occurrence, submissionID: submission.id, at: fixture.now.addingTimeInterval(120 + offset))
        return try #require(result.completionID)
    }

    private func expectTransactions(_ context: ModelContext, count: Int) throws {
        #expect(try context.fetchCount(FetchDescriptor<XPTransaction>()) == count)
        #expect(try context.fetchCount(FetchDescriptor<CoinTransaction>()) == count)
    }
}
