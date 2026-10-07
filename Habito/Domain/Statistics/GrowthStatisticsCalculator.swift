import Foundation

/// 仅消费已验证实例值和显式日期的确定性计算；不读取时钟/设备时区或重新展开模板。
nonisolated struct GrowthStatisticsCalculator {
    /// 公历日期标签运算与 DST、审核到账日无关；UTC 只是无歧义的日期表示，不是业务时区。
    ///
    /// - Parameters:
    ///   - end: 已由查询层使用注入业务日历/时区得到的“今天”。
    ///   - period: 含今天及此前 N-1 个日期。
    /// - Returns: 从最早日期到今天的完整日期标签，不补实例。
    /// - Throws: 日期边界超出 LocalDate 支持范围时抛出明确错误，不截短窗口。
    func dates(endingOn end: LocalDate, period: GrowthStatisticsPeriod) throws -> [LocalDate] {
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            throw GrowthStatisticsError.invalidWindowEnd(end)
        }
        calendar.timeZone = timeZone
        guard let anchor = calendar.date(from: DateComponents(year: end.year, month: end.month, day: end.day)) else {
            throw GrowthStatisticsError.invalidWindowEnd(end)
        }
        return try (0..<period.rawValue).reversed().map { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: anchor) else {
                throw GrowthStatisticsError.invalidWindowEnd(end)
            }
            let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day,
                (1...9999).contains(year), components.era == 1
            else { throw GrowthStatisticsError.invalidWindowEnd(end) }
            return try LocalDate(year: year, month: month, day: day)
        }
    }

    /// 先按所属日期选择窗口，再拒绝窗口内重复/矛盾输入；未来和窗口外历史不影响当前样本。
    ///
    /// - Returns: 总体、逐日、逐模板计数；比例由总分子/总分母计算，不平均每天的比例。
    /// - Throws: 重复 ID/模板日期或不可能的状态组合；不自动去重或改写输入。
    func snapshot(
        facts: [GrowthStatisticsFact], endingOn end: LocalDate, period: GrowthStatisticsPeriod
    ) throws -> GrowthStatisticsSnapshot {
        let dates = try dates(endingOn: end, period: period)
        guard let start = dates.first else { throw GrowthStatisticsError.invalidWindowEnd(end) }
        let selected = facts.filter { (start...end).contains($0.date) }
        try validate(selected)
        let groupedTasks = Dictionary(grouping: selected, by: \.templateID)
        let latestByTemplate = selected.reduce(into: [UUID: GrowthStatisticsFact]()) { latest, fact in
            if latest[fact.templateID].map({ $0.date < fact.date }) ?? true {
                latest[fact.templateID] = fact
            }
        }
        let tasks = latestByTemplate.values.map { latest in
            // 同模板同日已排除重复；按日期选择快照，与输入数组顺序和当前模板名称无关。
            let facts = groupedTasks[latest.templateID, default: []]
            return GrowthStatisticsTask(
                id: latest.templateID, title: latest.title, counts: GrowthStatisticsCounts(facts: facts),
                days: days(for: facts, dates: dates))
        }.sorted {
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id.uuidString < $1.id.uuidString
        }
        return GrowthStatisticsSnapshot(
            period: period, start: start, end: end, counts: GrowthStatisticsCounts(facts: selected),
            days: days(for: selected, dates: dates), tasks: tasks)
    }

    /// 单日概况复用同一事实校验，不为“今日”强行构造多日窗口。
    ///
    /// - Returns: 指定日期的计数；无实例保持无分母。
    /// - Throws: 当日重复ID/模板日期或矛盾事实。
    func day(facts: [GrowthStatisticsFact], on date: LocalDate) throws -> GrowthStatisticsDay {
        let selected = facts.filter { $0.date == date }
        try validate(selected)
        return GrowthStatisticsDay(date: date, counts: GrowthStatisticsCounts(facts: selected))
    }

    private func days(for facts: [GrowthStatisticsFact], dates: [LocalDate]) -> [GrowthStatisticsDay] {
        let grouped = Dictionary(grouping: facts, by: \.date)
        return dates.map { GrowthStatisticsDay(date: $0, counts: GrowthStatisticsCounts(facts: grouped[$0] ?? [])) }
    }

    private func validate(_ facts: [GrowthStatisticsFact]) throws {
        var identifiers: Set<UUID> = []
        var templateDates: [UUID: Set<LocalDate>] = [:]
        for fact in facts {
            guard identifiers.insert(fact.id).inserted else {
                throw GrowthStatisticsError.duplicateOccurrence(fact.id)
            }
            guard templateDates[fact.templateID, default: []].insert(fact.date).inserted else {
                throw GrowthStatisticsError.duplicateTemplateDate(fact.templateID, fact.date)
            }
            let isCompleted = fact.status == .completed
            guard isCompleted == (fact.completionTiming != nil), isCompleted == (fact.completionSource != nil),
                !fact.isAwaitingReview || (!isCompleted && fact.status != .skipped)
            else { throw GrowthStatisticsError.invalidFact(fact.id) }
        }
    }
}
