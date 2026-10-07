import Foundation
import Testing
@testable import Habito

/// 仅用固定日期和纯值；既不等待时钟，也不把合成数值当成产品默认值。
nonisolated struct GrowthStatisticsCalculatorTests {
    private let calculator = GrowthStatisticsCalculator()

    @Test("三窗口含两端，排除更早和未来实例", arguments: GrowthStatisticsPeriod.allCases)
    func includesExactDateEndpoints(period: GrowthStatisticsPeriod) throws {
        let end = try day("2026-10-07")
        let dates = try calculator.dates(endingOn: end, period: period)
        let start = try #require(dates.first)
        let facts = [
            try fact(date: start.dateKey, status: .completed, timing: .beforeReminder),
            try fact(date: end.dateKey),
            try fact(date: "2026-08-01"), try fact(date: "2026-10-08"),
        ]
        let result = try calculator.snapshot(facts: facts, endingOn: end, period: period)
        #expect(result.start == start && result.end == end)
        #expect(result.days.map(\.date) == dates)
        #expect(dates.count == period.rawValue && dates.last == end)
        #expect(result.counts.eligible == 2 && result.counts.completed == 1)
        #expect(result.counts.completionRate == 0.5 && result.counts.autonomyRate == 1)
    }

    @Test(
        "日期标签跨月跨年闰日和DST不按24小时回算",
        arguments: [
            ("2026-01-03", "2025-12-28"), ("2024-03-03", "2024-02-26"),
            ("2026-03-10", "2026-03-04"), ("2026-11-03", "2026-10-28"),
        ])
    func calendarDateWindows(pair: (String, String)) throws {
        let dates = try calculator.dates(endingOn: day(pair.0), period: .week)
        #expect(dates.first?.dateKey == pair.1)
        #expect(dates.count == 7 && Set(dates).count == 7)
        if pair.0 == "2024-03-03" { #expect(dates.contains(try day("2024-02-29"))) }
    }

    @Test("不支持的公元前窗口明确拒绝，不回绕成公元后")
    func refusesDateUnderflow() throws {
        let end = try day("0001-01-01")
        #expect(throws: GrowthStatisticsError.invalidWindowEnd(end)) {
            try calculator.dates(endingOn: end, period: .month)
        }
    }

    @Test("完成等待跳过与unknown使用不同分母")
    func mixedFactsHaveCorrectDenominators() throws {
        let facts = [
            try fact(status: .completed, timing: .beforeReminder),
            try fact(status: .completed, timing: .afterReminder, source: .parentApproval),
            try fact(status: .completed, timing: .unknown, source: .parentCorrection),
            try fact(awaiting: true), try fact(status: .inProgress), try fact(),
            try fact(status: .skipped),
        ]
        let counts = try snapshot(facts).counts
        #expect(counts.eligible == 6 && counts.completed == 3 && counts.skipped == 1)
        #expect(counts.awaitingReview == 1 && counts.autonomous == 1 && counts.knownTiming == 2)
        #expect(counts.unknownTiming == 1 && counts.completionRate == 0.5 && counts.autonomyRate == 0.5)
        #expect(counts.childConfirmed == 1 && counts.parentApproved == 1 && counts.parentCorrected == 1)
    }

    @Test(
        "完成来源不替代保存的自主性，unknown不等非自主",
        arguments: CompletionSource.allCases, CompletionTiming.allCases)
    func sourcesNeverInferTiming(source: CompletionSource, timing: CompletionTiming) throws {
        let counts = try snapshot([fact(status: .completed, timing: timing, source: source)]).counts
        #expect(counts.completed == 1 && counts.completionRate == 1)
        #expect(counts.knownTiming == (timing == .unknown ? 0 : 1))
        #expect(counts.autonomyRate == (timing == .unknown ? nil : (timing == .beforeReminder ? 1 : 0)))
    }

    @Test("空样本与只有跳过为空比例，有待完成样本则是0%", arguments: [false, true])
    func missingSamplesAreNotZero(skipped: Bool) throws {
        let empty = try snapshot(skipped ? [fact(status: .skipped)] : [])
        #expect(empty.counts.completionRate == nil && empty.counts.autonomyRate == nil)
        #expect(empty.days.allSatisfy { $0.counts.completionRate == nil })
        let pending = try snapshot([fact(awaiting: true)])
        #expect(pending.counts.completionRate == 0 && pending.counts.autonomyRate == nil)
    }

    @Test("总体比例按合计样本计算，不平均不同日期的百分比")
    func aggregateRatesAreWeightedBySamples() throws {
        let facts = [
            try fact(date: "2026-10-06", status: .completed, timing: .beforeReminder),
            try fact(status: .completed, timing: .afterReminder), try fact(), try fact(),
        ]
        let result = try snapshot(facts)
        #expect(result.counts.completionRate == 0.5)
        #expect(result.days.suffix(2).map(\.counts.eligible) == [1, 3])
        #expect(result.counts.autonomyRate == 0.5)
    }

    @Test("稳定模板聚合历史改名，最新快照与排序不随输入顺序变化")
    func renamingKeepsStableTemplateAndTrend() throws {
        let template = UUID()
        let facts = [
            try fact(template: template, date: "2026-10-06", title: "旧名字"),
            try fact(template: template, title: "新名字", status: .completed, timing: .beforeReminder),
            try fact(title: "A任务"),
        ]
        let original = try snapshot(facts)
        #expect(original == (try snapshot(Array(facts.reversed()))))
        #expect(original.tasks.map(\.title) == ["A任务", "新名字"])
        let renamed = try #require(original.tasks.first { $0.id == template })
        #expect(renamed.counts.eligible == 2 && renamed.counts.completed == 1)
        #expect(renamed.days.count == 7 && renamed.days.suffix(2).allSatisfy { $0.counts.eligible == 1 })
        #expect(renamed.days.dropLast(2).allSatisfy { $0.counts.completionRate == nil })
    }

    @Test("相同标题的不同模板不合并，排序用稳定ID")
    func sameTitleDoesNotMergeDifferentTemplates() throws {
        let result = try snapshot([fact(title: "同名"), fact(title: "同名")])
        #expect(result.tasks.count == 2)
        #expect(result.tasks.map(\.id.uuidString) == result.tasks.map(\.id.uuidString).sorted())
    }

    @Test("重复实例ID明确拒绝，而不是静默去重")
    func duplicateOccurrenceIsRejected() throws {
        let original = try fact()
        #expect(throws: GrowthStatisticsError.duplicateOccurrence(original.id)) {
            try snapshot([original, original])
        }
    }

    @Test("同模板同日期两个实例明确拒绝")
    func duplicateTemplateDateIsRejected() throws {
        let template = UUID()
        let date = try day("2026-10-07")
        #expect(throws: GrowthStatisticsError.duplicateTemplateDate(template, date)) {
            try snapshot([fact(template: template), fact(template: template)])
        }
    }

    @Test("完成缺证据和未完成携带完成证据都拒绝", arguments: [0, 1, 2, 3, 4, 5])
    func contradictoryFactsAreRejected(variant: Int) throws {
        let value = GrowthStatisticsFact(
            id: UUID(), templateID: UUID(), date: try day("2026-10-07"), title: "合成",
            status: variant < 3 ? .completed : (variant == 5 ? .skipped : .pending),
            isAwaitingReview: variant == 2 || variant == 5,
            completionTiming: variant == 0 || variant == 3 || variant == 5 ? nil : .beforeReminder,
            completionSource: variant == 1 || variant == 4 || variant == 5 ? nil : .childManual)
        #expect(throws: GrowthStatisticsError.invalidFact(value.id)) { try snapshot([value]) }
    }

    @Test("撤销后的当前pending事实不叠加先前完成")
    func revokedCurrentFactDoesNotCountOldCompletion() throws {
        let id = UUID()
        let template = UUID()
        let confirmed = try snapshot([fact(id: id, template: template, status: .completed, timing: .beforeReminder)])
        let revoked = try snapshot([fact(id: id, template: template)])
        #expect(confirmed.counts.completed == 1 && revoked.counts.completed == 0)
        #expect(revoked.counts.eligible == 1 && revoked.counts.autonomyRate == nil)
    }

    private func day(_ value: String) throws -> LocalDate { try LocalDate(dateKey: value) }

    private func snapshot(_ facts: [GrowthStatisticsFact]) throws -> GrowthStatisticsSnapshot {
        try calculator.snapshot(facts: facts, endingOn: day("2026-10-07"), period: .week)
    }

    private func fact(
        id: UUID = UUID(), template: UUID = UUID(), date: String = "2026-10-07", title: String = "合成任务",
        status: TaskOccurrenceStatus = .pending, awaiting: Bool = false,
        timing: CompletionTiming? = nil, source: CompletionSource = .childManual
    ) throws -> GrowthStatisticsFact {
        GrowthStatisticsFact(
            id: id, templateID: template, date: try day(date), title: title, status: status,
            isAwaitingReview: awaiting, completionTiming: timing,
            completionSource: status == .completed ? source : nil)
    }
}
