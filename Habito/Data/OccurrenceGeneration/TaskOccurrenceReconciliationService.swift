import Foundation
import SwiftData

/// 在明确日期范围内把目标候选幂等核对到 SwiftData 实例。
///
/// 服务归属主 actor，因为 `ModelContext` 及其模型对象不能跨并发域共享。所有变更在
/// 一次 `save()` 中提交；相同稳定键始终原位更新，以保留实例身份和关联数据。
@MainActor
struct TaskOccurrenceReconciliationService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// 核对一个模板在指定日期范围内的实例。
    ///
    /// - Parameters:
    ///   - template: 提供稳定 ID、当前修订和最新快照字段的模板。
    ///   - candidates: 已应用日期/单日覆盖的目标候选。
    ///   - range: 本次允许创建、更新或删除的闭合日期范围。
    ///   - today: 注入的业务今天；早于它的实例一律视为历史。
    ///   - now: 注入的写入时间，测试不可依赖真实时钟。
    ///   - savesChanges: 是否在本次核对后立即保存。复合事务可传入 `false`，
    ///     待多个模板全部核对成功后由外层统一提交。
    /// - Returns: 实际插入、更新、删除和受保护的数量。
    /// - Throws: 输入冲突、模板配置/奖励或存量状态损坏，以及 SwiftData 保存失败。
    func reconcile(
        template: TaskTemplate,
        candidates: [ResolvedTaskCandidate],
        in range: ClosedRange<LocalDate>,
        today: LocalDate,
        now: Date,
        savesChanges: Bool = true
    ) throws -> OccurrenceReconciliationReport {
        guard template.lifecycleState == .active || candidates.isEmpty else {
            throw OccurrenceReconciliationError.inactiveTemplateHasCandidates
        }

        // 配置先整体验证，不能在候选遍历中才发现坏奖励并留下前几天的半更新。
        try validateConfiguration(of: template)

        let desired = try validatedCandidates(
            candidates,
            range: range,
            today: today,
            template: template
        )
        let templateID = template.id
        let descriptor = FetchDescriptor<TaskOccurrence>(
            predicate: #Predicate { $0.templateID == templateID }
        )
        let existing = try context.fetch(descriptor)
        // 先完整验证存量字段，再执行任何修改，确保领域数据损坏不会留下半更新上下文。
        var existingByDate = try validatedExistingOccurrences(existing)
        var inserted = 0
        var updated = 0
        var deleted = 0
        var protected = 0

        for candidate in desired.values {
            if let existingState = existingByDate.removeValue(forKey: candidate.date.dateKey) {
                let occurrence = existingState.occurrence
                let status = existingState.status
                // 退回或撤销后仍保留原实例配置；pending 并不代表从未提交或完成。
                guard candidate.date >= today, status == .pending, !occurrence.isDetachedOverride,
                    !existingState.preservesHistory
                else {
                    protected += 1
                    continue
                }
                if needsUpdate(candidate, template: template, occurrence: occurrence) {
                    apply(candidate, template: template, to: occurrence, now: now)
                    updated += 1
                }
            } else {
                let occurrence = makeOccurrence(candidate, template: template, now: now)
                context.insert(occurrence)
                inserted += 1
            }
        }

        for existingState in existingByDate.values {
            let occurrence = existingState.occurrence
            let date = existingState.date
            guard range.contains(date) else {
                continue
            }
            let status = existingState.status
            if date >= today, status == .pending, !occurrence.isDetachedOverride, !existingState.preservesHistory {
                try TaskGraphDeletionService(context: context).stageOccurrenceDeletion(occurrence)
                deleted += 1
            } else {
                protected += 1
            }
        }

        if savesChanges {
            try context.save()
        }
        return .init(
            insertedCount: inserted,
            updatedCount: updated,
            deletedCount: deleted,
            protectedCount: protected
        )
    }

    /// 只允许已支持的分类/时段/P0 验收，并确保任何自主提交都能安全加总 Coin。
    ///
    /// - Throws: 损坏类型、负金额或 Coin 总额溢出；不修复、截断或猜测产品默认值。
    private func validateConfiguration(of template: TaskTemplate) throws {
        for (field, rawValue, isValid) in [
            ("category", template.categoryRawValue, template.category != nil),
            ("timePeriod", template.timePeriodRawValue, template.timePeriod != nil),
            ("verificationType", template.verificationTypeRawValue, template.verificationType != nil),
        ] {
            guard isValid else {
                throw OccurrenceReconciliationError.invalidTemplateConfiguration(
                    templateID: template.id, field: field, rawValue: rawValue)
            }
        }
        guard template.xpReward >= 0, template.coinReward >= 0, template.activeBonusCoin >= 0 else {
            throw RewardLedgerError.invalidAmount
        }
        // 即使本次提醒已过，也检查最大可能到账；未来自主完成不能才发现配置不可结算。
        guard !template.coinReward.addingReportingOverflow(template.activeBonusCoin).overflow else {
            throw RewardLedgerError.integerOverflow
        }
    }

    private func validatedExistingOccurrences(
        _ occurrences: [TaskOccurrence]
    ) throws -> [String: (
        occurrence: TaskOccurrence, date: LocalDate, status: TaskOccurrenceStatus,
        preservesHistory: Bool
    )] {
        var result: [String: (TaskOccurrence, LocalDate, TaskOccurrenceStatus, Bool)] = [:]
        let history = TaskSubmissionHistory(context: context)
        for occurrence in occurrences {
            let date: LocalDate
            do {
                date = try LocalDate(dateKey: occurrence.dateKey)
            } catch {
                throw OccurrenceReconciliationError.invalidStoredDateKey(
                    occurrenceID: occurrence.id,
                    dateKey: occurrence.dateKey
                )
            }
            guard let status = occurrence.status else {
                throw OccurrenceReconciliationError.invalidStoredStatus(
                    occurrenceID: occurrence.id,
                    rawValue: occurrence.statusRawValue
                )
            }
            // 修改前验证全部等待事实；坏历史不能导致先改一半实例再报错。
            let preservesHistory = try history.preservesOccurrenceHistory(occurrence)
            result[occurrence.dateKey] = (occurrence, date, status, preservesHistory)
        }
        return result
    }

    private func validatedCandidates(
        _ candidates: [ResolvedTaskCandidate],
        range: ClosedRange<LocalDate>,
        today: LocalDate,
        template: TaskTemplate
    ) throws -> [LocalDate: ResolvedTaskCandidate] {
        var result: [LocalDate: ResolvedTaskCandidate] = [:]
        for candidate in candidates {
            guard range.contains(candidate.date) else {
                throw OccurrenceReconciliationError.candidateOutsideRange(candidate.date)
            }
            guard candidate.date >= today else {
                throw OccurrenceReconciliationError.candidateBeforeToday(candidate.date)
            }
            for (field, value) in [
                ("scheduledAt", Optional(candidate.scheduledAt)),
                ("plannedAt", candidate.plannedAt), ("deadlineAt", candidate.deadlineAt),
            ] {
                if let value, !value.timeIntervalSinceReferenceDate.isFinite {
                    throw OccurrenceReconciliationError.invalidCandidateTime(date: candidate.date, field: field)
                }
            }
            guard result[candidate.date] == nil else {
                throw OccurrenceReconciliationError.duplicateCandidateDate(candidate.date)
            }
            if case .generated(let revision) = candidate.origin, revision != template.revision {
                throw OccurrenceReconciliationError.candidateRevisionMismatch(
                    candidate: revision,
                    template: template.revision
                )
            }
            result[candidate.date] = candidate
        }
        return result
    }

    private func makeOccurrence(
        _ candidate: ResolvedTaskCandidate,
        template: TaskTemplate,
        now: Date
    ) -> TaskOccurrence {
        let occurrence = TaskOccurrence(
            templateID: template.id,
            date: candidate.date,
            scheduledAt: candidate.scheduledAt,
            titleSnapshot: template.title,
            iconSnapshot: template.iconName,
            colorSnapshot: template.colorToken,
            targetDurationSnapshot: template.targetDurationSeconds,
            sourceRevision: sourceRevision(for: candidate, template: template),
            isDetachedOverride: candidate.origin == .detachedOverride,
            createdAt: now,
            updatedAt: now,
            xpRewardSnapshot: template.xpReward,
            coinRewardSnapshot: template.coinReward,
            activeBonusCoinSnapshot: template.activeBonusCoin,
            plannedAt: candidate.plannedAt,
            deadlineAt: candidate.deadlineAt
        )
        // 已在修改前验证原始值；直接复制能保留明确输入，不用后来的模板回算已生成实例。
        occurrence.categorySnapshotRawValue = template.categoryRawValue
        occurrence.timePeriodSnapshotRawValue = template.timePeriodRawValue
        occurrence.verificationTypeSnapshotRawValue = template.verificationTypeRawValue
        occurrence.template = template
        return occurrence
    }

    private func apply(
        _ candidate: ResolvedTaskCandidate,
        template: TaskTemplate,
        to occurrence: TaskOccurrence,
        now: Date
    ) {
        occurrence.scheduledAt = candidate.scheduledAt
        occurrence.plannedAt = candidate.plannedAt
        occurrence.deadlineAt = candidate.deadlineAt
        occurrence.titleSnapshot = template.title
        occurrence.iconSnapshot = template.iconName
        occurrence.colorSnapshot = template.colorToken
        occurrence.targetDurationSnapshot = template.targetDurationSeconds
        occurrence.categorySnapshotRawValue = template.categoryRawValue
        occurrence.timePeriodSnapshotRawValue = template.timePeriodRawValue
        occurrence.verificationTypeSnapshotRawValue = template.verificationTypeRawValue
        occurrence.xpRewardSnapshot = template.xpReward
        occurrence.coinRewardSnapshot = template.coinReward
        occurrence.activeBonusCoinSnapshot = template.activeBonusCoin
        occurrence.sourceRevision = sourceRevision(for: candidate, template: template)
        occurrence.isDetachedOverride = candidate.origin == .detachedOverride
        occurrence.updatedAt = now
        occurrence.template = template
    }

    private func needsUpdate(
        _ candidate: ResolvedTaskCandidate,
        template: TaskTemplate,
        occurrence: TaskOccurrence
    ) -> Bool {
        occurrence.scheduledAt != candidate.scheduledAt
            || occurrence.plannedAt != candidate.plannedAt
            || occurrence.deadlineAt != candidate.deadlineAt
            || occurrence.titleSnapshot != template.title
            || occurrence.iconSnapshot != template.iconName
            || occurrence.colorSnapshot != template.colorToken
            || occurrence.targetDurationSnapshot != template.targetDurationSeconds
            || occurrence.categorySnapshotRawValue != template.categoryRawValue
            || occurrence.timePeriodSnapshotRawValue != template.timePeriodRawValue
            || occurrence.verificationTypeSnapshotRawValue != template.verificationTypeRawValue
            || occurrence.xpRewardSnapshot != template.xpReward
            || occurrence.coinRewardSnapshot != template.coinReward
            || occurrence.activeBonusCoinSnapshot != template.activeBonusCoin
            || occurrence.sourceRevision != sourceRevision(for: candidate, template: template)
            || occurrence.isDetachedOverride != (candidate.origin == .detachedOverride)
            || occurrence.template?.id != template.id
    }

    private func sourceRevision(
        for candidate: ResolvedTaskCandidate,
        template: TaskTemplate
    ) -> Int {
        if case .generated(let revision) = candidate.origin {
            revision
        } else {
            template.revision
        }
    }
}
