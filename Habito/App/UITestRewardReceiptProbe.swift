#if DEBUG
    import Foundation
    import SwiftData

    /// 显式隔离启动探针：在不同 App 进程中核对同一真实收据，不给生产页面增加测试按钮。
    ///
    /// - Important: 只从 UI 测试组合根调用，使用其独占数据库。任一断言失败就拒绝启动，不能假报成功。
    @MainActor
    enum UITestRewardReceiptProbe: String, CaseIterable {
        case seed
        case pending
        case failedAcknowledgement = "failed-acknowledgement"
        case acknowledge
        case acknowledged

        static let argument = "--habito-ui-receipt-probe"

        /// 缺少探针参数时不访问数据库；坏参数明确失败，不回退到正式库。
        static func prepare(context: ModelContext, arguments: [String]) throws {
            guard let index = arguments.firstIndex(of: argument) else { return }
            guard arguments.contains(UITestLaunchConfiguration.enableArgument),
                arguments.indices.contains(index + 1), let phase = Self(rawValue: arguments[index + 1])
            else { throw CocoaError(.coderInvalidValue) }
            guard !context.hasChanges else { throw RewardLedgerError.pendingContextChanges }
            try phase.verify(context: context)
        }

        private func verify(context: ModelContext) throws {
            let taskID = UITestSeedService.taskID
            guard
                let occurrence = try context.fetch(
                    FetchDescriptor<TaskOccurrence>(predicate: #Predicate { $0.id == taskID })
                ).first
            else { throw CocoaError(.coderInvalidValue) }
            let service = ChildRewardReceiptService(context: context)
            if self == .seed {
                guard try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 0 else {
                    throw CocoaError(.coderInvalidValue)
                }
                // 固定在原夹具创建时刻提交，不用跨进程的实际等待时间解释自主性。
                let submission = try TaskSubmissionService(context: context).submit(
                    occurrence, at: occurrence.createdAt)
                _ = try TaskSubmissionReviewService(context: context).approve(
                    occurrence, submissionID: submission.submissionID,
                    at: occurrence.createdAt.addingTimeInterval(1))
            }
            guard let record = occurrence.completionRecord, let settledAt = record.rewardSettledAt,
                record.childFeedbackDeliveryVersion == 1,
                try context.fetchCount(FetchDescriptor<CompletionRecord>()) == 1
            else { throw CocoaError(.coderInvalidValue) }
            _ = try TaskCompletionAuditValidator(context: context).validate(record)
            if self == .failedAcknowledgement {
                let failing = ChildRewardReceiptService(
                    context: context,
                    saveChanges: { _ in
                        throw NSError(domain: "HabitoSyntheticProcessReceiptSave", code: 1)
                    })
                do {
                    _ = try failing.acknowledge(completionID: record.id, at: settledAt.addingTimeInterval(60))
                    throw CocoaError(.coderInvalidValue)
                } catch let error as NSError {
                    guard error.domain == "HabitoSyntheticProcessReceiptSave" else { throw error }
                }
            } else if self == .acknowledge {
                guard try service.acknowledge(completionID: record.id, at: settledAt.addingTimeInterval(60)) else {
                    throw CocoaError(.coderInvalidValue)
                }
            }
            let pending = try service.pendingReceipts()
            if self == .acknowledge || self == .acknowledged {
                guard pending.isEmpty, record.childFeedbackAcknowledgedAt == settledAt.addingTimeInterval(60) else {
                    throw CocoaError(.coderInvalidValue)
                }
            } else {
                guard pending.map(\.completionID) == [record.id], record.childFeedbackAcknowledgedAt == nil else {
                    throw CocoaError(.coderInvalidValue)
                }
            }
            // 每个新进程重新审计交易数量及金额，确认显示/失败/确认均没有再次结算。
            guard try context.fetchCount(FetchDescriptor<XPTransaction>()) == 1,
                try context.fetchCount(FetchDescriptor<CoinTransaction>()) == 1,
                try RewardLedgerService(context: context).balance()
                    == RewardBalance(effectiveXP: record.xpRewardSnapshot, coins: record.settledCoinSnapshot),
                !context.hasChanges
            else { throw CocoaError(.coderInvalidValue) }
        }
    }
#endif
