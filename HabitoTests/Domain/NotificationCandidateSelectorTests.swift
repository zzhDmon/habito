import Foundation
import Testing
@testable import Habito

@Suite("通知滚动候选选择")
struct NotificationCandidateSelectorTests {
    @Test("预算边界日完整或部分覆盖按当天剩余请求判断", arguments: [true, false])
    func completeBoundaryDayDoesNotReportPartialCoverage(hasUnselectedTaskOnBoundary: Bool) throws {
        let dates = try ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"]
            .map { try LocalDate(dateKey: $0) }
        let availableThrough = try LocalDate(dateKey: "2026-10-06")
        let boundary = try #require(dates.last)
        var candidates: [NotificationSchedulingCandidate] = []
        for (dayIndex, date) in dates.enumerated() {
            let instant = try Date("\(date.dateKey)T11:30:00Z", strategy: .iso8601)
            for index in 0..<8 {
                candidates.append(candidate(index: UInt8(dayIndex * 8 + index + 1), date: date, at: instant))
            }
        }
        let unselectedDate = hasUnselectedTaskOnBoundary ? boundary : availableThrough
        candidates.append(
            candidate(
                index: 49, date: unselectedDate, at: try Date("\(unselectedDate.dateKey)T11:30:00Z", strategy: .iso8601)
            ))
        let result = try NotificationCandidateSelector().select(
            from: Array(candidates.reversed()), now: Date("2026-09-30T00:00:00Z", strategy: .iso8601),
            availableThrough: availableThrough, minimumCoverageThrough: boundary)
        #expect(result.primaryCandidates.count == 48)
        #expect(result.coverageThrough == boundary)
        #expect(result.isCoverageBoundaryPartial == hasUnselectedTaskOnBoundary)
        #expect(result.hasMinimumCoverage == !hasUnselectedTaskOnBoundary)
    }

    @Test("高任务量受限且同一时刻稳定排序")
    func limitsAndSorts() throws {
        let date = try LocalDate(dateKey: "2026-09-30")
        let candidates = (0..<60).reversed().map { index in
            NotificationSchedulingCandidate(
                occurrenceID: UUID(
                    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index + 1))
                ),
                date: date,
                scheduledAt: Date(timeIntervalSince1970: 1_800_000_100)
            )
        }
        let result = try NotificationCandidateSelector().select(
            from: candidates,
            now: Date(timeIntervalSince1970: 1_800_000_000),
            availableThrough: date,
            minimumCoverageThrough: date
        )
        #expect(result.primaryCandidates.count == 48)
        #expect(result.primaryCandidates.first?.occurrenceID.uuidString.hasSuffix("000000000001") == true)
        #expect(result.isCoverageBoundaryPartial)
        #expect(!result.hasMinimumCoverage)
    }

    @Test("跨月完整覆盖与不足七天可区分")
    func coverageAcrossMonth() throws {
        let start = try LocalDate(dateKey: "2026-09-30")
        let next = try LocalDate(dateKey: "2026-10-01")
        let selector = NotificationCandidateSelector()
        let full = try selector.select(
            from: [], now: Date(timeIntervalSince1970: 1_800_000_000), availableThrough: next,
            minimumCoverageThrough: start
        )
        let insufficient = try selector.select(
            from: [], now: Date(timeIntervalSince1970: 1_800_000_000), availableThrough: start,
            minimumCoverageThrough: next
        )
        #expect(full.coverageThrough == next)
        #expect(full.hasMinimumCoverage)
        #expect(!insufficient.hasMinimumCoverage)
    }

    @Test("重复实例与越界候选显式失败")
    func rejectsInvalidInputs() throws {
        let date = try LocalDate(dateKey: "2026-09-30")
        let next = try LocalDate(dateKey: "2026-10-01")
        let id = UUID()
        let candidate = NotificationSchedulingCandidate(
            occurrenceID: id, date: next, scheduledAt: Date(timeIntervalSince1970: 1_800_000_060)
        )
        let selector = NotificationCandidateSelector()
        #expect(throws: NotificationCandidateSelectionError.duplicateOccurrenceID(id)) {
            try selector.select(
                from: [candidate, candidate], now: .distantPast, availableThrough: next, minimumCoverageThrough: date)
        }
        #expect(throws: NotificationCandidateSelectionError.candidateBeyondAvailableHorizon(id)) {
            try selector.select(
                from: [candidate], now: .distantPast, availableThrough: date, minimumCoverageThrough: date)
        }
    }

    private func candidate(index: UInt8, date: LocalDate, at instant: Date) -> NotificationSchedulingCandidate {
        NotificationSchedulingCandidate(
            occurrenceID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, index)),
            date: date, scheduledAt: instant)
    }
}
