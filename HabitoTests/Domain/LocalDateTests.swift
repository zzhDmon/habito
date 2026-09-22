import Foundation
import Testing
@testable import Habito

@Suite("本地日期")
struct LocalDateTests {
    @Test("合法闰日可稳定往返日期键")
    func leapDayRoundTripsDateKey() throws {
        let date = try LocalDate(year: 2028, month: 2, day: 29)

        #expect(date.dateKey == "2028-02-29")
        #expect(try LocalDate(dateKey: date.dateKey) == date)
    }

    @Test("不存在的日期会明确拒绝")
    func rejectsInvalidCalendarDate() {
        #expect(throws: LocalDateError.self) {
            try LocalDate(year: 2027, month: 2, day: 29)
        }
    }

    @Test("日期键必须使用固定宽度格式")
    func rejectsNonCanonicalDateKey() {
        #expect(throws: LocalDateError.invalidDateKey("2026-9-2")) {
            try LocalDate(dateKey: "2026-9-2")
        }
    }

    @Test("同一绝对时间按注入时区得到不同本地日期")
    func extractsDateUsingInjectedTimeZone() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-22T16:30:00Z"))
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let calendar = Calendar(identifier: .gregorian)

        let shanghaiDate = try LocalDate(date: instant, calendar: calendar, timeZone: shanghai)
        let losAngelesDate = try LocalDate(date: instant, calendar: calendar, timeZone: losAngeles)

        #expect(shanghaiDate.dateKey == "2026-09-23")
        #expect(losAngelesDate.dateKey == "2026-09-22")
    }
}
