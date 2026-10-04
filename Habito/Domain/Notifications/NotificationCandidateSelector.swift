import Foundation

/// 在系统请求预算内确定性选择最近的未来主提醒。
nonisolated struct NotificationCandidateSelector: Sendable {
    static let primaryLimit = 48
    static let snoozeReserve = 8

    /// 选择主提醒并计算覆盖边界。
    ///
    /// - Parameters:
    ///   - candidates: 已物化实例的主提醒候选。
    ///   - now: 当前绝对时间；到点及过去候选不再进入未来排程。
    ///   - availableThrough: 调用方已生成并检查实例的最远本地日期。
    ///   - minimumCoverageThrough: 家长中心要求完整覆盖的最低日期，通常为今天加七天。
    ///   - primaryLimit: 主提醒槽位上限，默认 48；剩余槽位由稍后提醒和系统余量使用。
    /// - Returns: 稳定排序的候选与诚实覆盖边界。
    /// - Throws: 输入重复、越过已知实例范围或预算无效时抛出错误。
    func select(
        from candidates: [NotificationSchedulingCandidate],
        now: Date,
        availableThrough: LocalDate,
        minimumCoverageThrough: LocalDate,
        primaryLimit: Int = Self.primaryLimit
    ) throws -> NotificationCandidateSelection {
        guard primaryLimit > 0 else {
            throw NotificationCandidateSelectionError.invalidPrimaryLimit(primaryLimit)
        }

        var seen = Set<UUID>()
        for candidate in candidates {
            guard seen.insert(candidate.occurrenceID).inserted else {
                throw NotificationCandidateSelectionError.duplicateOccurrenceID(candidate.occurrenceID)
            }
            guard candidate.date <= availableThrough else {
                throw NotificationCandidateSelectionError.candidateBeyondAvailableHorizon(
                    candidate.occurrenceID
                )
            }
        }

        let future =
            candidates
            .filter { $0.scheduledAt > now }
            .sorted {
                if $0.scheduledAt != $1.scheduledAt { return $0.scheduledAt < $1.scheduledAt }
                return $0.occurrenceID.uuidString < $1.occurrenceID.uuidString
            }
        let selected = Array(future.prefix(primaryLimit))
        let wasTruncated = future.count > selected.count
        let coverageThrough = wasTruncated ? selected.last?.date ?? availableThrough : availableThrough
        // 预算截断不等于边界日缺漏；只有下一个未选候选仍在当天，才是部分日覆盖。
        let isPartial = future.dropFirst(selected.count).first?.date == coverageThrough
        let hasMinimumCoverage =
            coverageThrough > minimumCoverageThrough
            || (coverageThrough == minimumCoverageThrough && !isPartial)

        return NotificationCandidateSelection(
            primaryCandidates: selected,
            coverageThrough: coverageThrough,
            isCoverageBoundaryPartial: isPartial,
            hasMinimumCoverage: hasMinimumCoverage
        )
    }
}
