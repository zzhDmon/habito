/// 为单个模板合并普通候选、日期类型覆盖与 detached 单日候选。
///
/// 优先级固定为：detached 单日候选 > 放假过滤 > 模板普通候选。调用方每次应传入
/// 完整的当前覆盖集合，因此删除放假覆盖后重新执行即可恢复普通候选，不需要保存额外状态。
nonisolated struct TaskCandidateOverrideResolver: Sendable {
    /// 应用覆盖并返回按日期升序排列的候选。
    ///
    /// - Parameters:
    ///   - generated: 当前模板由重复规则展开出的普通候选。
    ///   - templateRevision: 生成普通候选时对应的模板版本，供 M1-005 判断同步边界。
    ///   - dayOverrides: 范围内的上课或放假日期覆盖。
    ///   - detachedOverrides: 家长为当前模板单独修改、恢复或新增的日期候选。
    /// - Returns: 已应用覆盖的候选；单日候选会替换同日普通候选。
    /// - Throws: 任一输入在同一天出现多条记录时抛出 `TaskCandidateOverrideError`，
    ///   避免依赖数组顺序静默选择结果。
    func resolve(
        generated: [ScheduledTaskCandidate],
        templateRevision: Int,
        dayOverrides: [DayTypeOverrideValue],
        detachedOverrides: [ScheduledTaskCandidate]
    ) throws -> [ResolvedTaskCandidate] {
        let generatedByDate = try uniqueCandidates(
            generated,
            duplicateError: TaskCandidateOverrideError.duplicateGeneratedDate
        )
        let detachedByDate = try uniqueCandidates(
            detachedOverrides,
            duplicateError: TaskCandidateOverrideError.duplicateDetachedDate
        )
        let dayTypeByDate = try uniqueDayOverrides(dayOverrides)

        var resolved: [LocalDate: ResolvedTaskCandidate] = [:]

        for (date, candidate) in generatedByDate
        where dayTypeByDate[date] != .holiday {
            resolved[date] = ResolvedTaskCandidate(
                date: candidate.date,
                scheduledAt: candidate.scheduledAt,
                origin: .generated(templateRevision: templateRevision)
            )
        }

        // detached 表达家长对这一天的明确意图，因此即使当天是放假也必须保留。
        for (date, candidate) in detachedByDate {
            resolved[date] = ResolvedTaskCandidate(
                date: candidate.date,
                scheduledAt: candidate.scheduledAt,
                origin: .detachedOverride
            )
        }

        return resolved.values.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.scheduledAt < rhs.scheduledAt
        }
    }

    private func uniqueCandidates(
        _ candidates: [ScheduledTaskCandidate],
        duplicateError: (LocalDate) -> TaskCandidateOverrideError
    ) throws -> [LocalDate: ScheduledTaskCandidate] {
        var result: [LocalDate: ScheduledTaskCandidate] = [:]
        for candidate in candidates {
            guard result[candidate.date] == nil else {
                throw duplicateError(candidate.date)
            }
            result[candidate.date] = candidate
        }
        return result
    }

    private func uniqueDayOverrides(
        _ overrides: [DayTypeOverrideValue]
    ) throws -> [LocalDate: DayType] {
        var result: [LocalDate: DayType] = [:]
        for override in overrides {
            guard result[override.date] == nil else {
                throw TaskCandidateOverrideError.duplicateDayOverride(override.date)
            }
            result[override.date] = override.dayType
        }
        return result
    }
}
