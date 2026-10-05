import Foundation
import Testing
import UserNotifications
@testable import Habito

@Suite("系统任务通知请求转换")
@MainActor
struct LocalNotificationRequestTests {
    @Test("标准主/稍后系统请求的快照直接还原明确绝对日期", arguments: [NotificationKind.primary, .snooze])
    func normalizedSnapshotDoesNotReadCurrentTime(_ kind: NotificationKind) throws {
        let date = try Date("2026-03-08T10:05:00Z", strategy: .iso8601)
        let request = request(at: date, kind: kind)
        let snapshot = LocalNotificationService.makePendingNotificationSnapshot(
            LocalNotificationService.makeTaskNotificationRequest(request))
        #expect(snapshot.identifier == request.identifier)
        #expect(snapshot.title == request.title)
        #expect(snapshot.body == request.body)
        #expect(snapshot.scheduledAt == date)
    }

    @Test("浮动日历旧请求或重复请求均标为不可确认，完整单次请求保留", arguments: [true, false], [true, false])
    func nonAbsoluteCalendarSnapshotNeedsReplacement(omitContext: Bool, repeats: Bool) throws {
        let date = try Date("2026-11-01T09:30:00Z", strategy: .iso8601)
        let original = LocalNotificationService.makeTaskNotificationRequest(request(at: date))
        var components = try #require(original.trigger as? UNCalendarNotificationTrigger).dateComponents
        if omitContext {
            components.calendar = nil
            components.timeZone = nil
        }
        let modified = UNNotificationRequest(
            identifier: original.identifier, content: original.content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
        let snapshot = LocalNotificationService.makePendingNotificationSnapshot(modified)
        #expect(snapshot.scheduledAt == (omitContext || repeats ? nil : date))
    }

    @Test("不完整日历、相对间隔和缺失触发器不能伪装成固定绝对日期")
    func incompleteOrUnsupportedTriggerNeedsReplacement() throws {
        let date = try Date("2026-11-01T09:30:00Z", strategy: .iso8601)
        let original = LocalNotificationService.makeTaskNotificationRequest(request(at: date))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(calendar: calendar, timeZone: .gmt, hour: 9)
        let triggers: [UNNotificationTrigger?] = [
            UNCalendarNotificationTrigger(dateMatching: components, repeats: false),
            UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false), nil,
        ]
        for trigger in triggers {
            let modified = UNNotificationRequest(
                identifier: original.identifier, content: original.content, trigger: trigger)
            #expect(LocalNotificationService.makePendingNotificationSnapshot(modified).scheduledAt == nil)
        }
    }

    @Test("单次触发器显式保留解释年月日的日历与时区")
    func calendarTriggerCarriesExplicitInterpretation() throws {
        let date = try Date("2026-11-01T09:30:00Z", strategy: .iso8601)
        let trigger = try trigger(for: date)
        let calendar = try #require(trigger.dateComponents.calendar)
        let timeZone = try #require(trigger.dateComponents.timeZone)
        #expect(calendar.identifier == .gregorian)
        #expect(timeZone.secondsFromGMT(for: date) == 0)
        #expect(calendar.timeZone == timeZone)
        #expect(!trigger.repeats)
    }

    @Test(
        "触发组件能独立还原业务绝对时间，不依赖系统当前时间",
        arguments: [
            "2026-09-27T11:30:00Z", "2026-11-01T08:30:00Z", "2026-11-01T09:30:00Z",
            "2026-03-08T10:05:00Z", "2026-12-31T23:59:59Z",
        ])
    func triggerRoundTripsAbsoluteSchedule(_ timestamp: String) throws {
        let date = try Date(timestamp, strategy: .iso8601)
        let components = try trigger(for: date).dateComponents
        let reconstructed = try #require(components.date)
        // 系统日历触发精度为秒；与协调器已有的小于一秒比较门槛一致，不改变十分钟业务计算。
        #expect(abs(reconstructed.timeIntervalSince(date)) < 1)
    }

    @Test("带小数秒的稍后时刻仅舍弃不足一秒，不跳到下一日")
    func fractionalSecondsKeepReconciliationTolerance() throws {
        // iOS 17 的默认 ISO8601 策略不接受小数秒；夹具先解析整秒再相加，避免测试解析差异。
        let date = try Date("2026-12-31T23:59:59Z", strategy: .iso8601).addingTimeInterval(0.123)
        let reconstructed = try #require(trigger(for: date).dateComponents.date)
        #expect(abs(reconstructed.timeIntervalSince(date)) < 1)
        #expect(reconstructed <= date)
        #expect(reconstructed == date.addingTimeInterval(-0.123))
    }

    @Test("安全归档重开后触发器仍保留绝对时间", arguments: ["2026-11-01T08:30:00Z", "2026-11-01T09:30:00Z"])
    func archivedTriggerPreservesAbsoluteSchedule(_ timestamp: String) throws {
        let date = try Date(timestamp, strategy: .iso8601)
        let original = try trigger(for: date)
        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: UNCalendarNotificationTrigger.self, from: data)
        let reopened = try #require(decoded)
        #expect(reopened.dateComponents == original.dateComponents)
        #expect(reopened.dateComponents.date == date)
        #expect(!reopened.repeats)
    }

    @Test("夏令时回拨两个同名本地小时仍保持不同的绝对通知时刻")
    func repeatedLocalHourDoesNotCollapseTwoInstants() throws {
        let first = try Date("2026-11-01T08:30:00Z", strategy: .iso8601)
        let second = try Date("2026-11-01T09:30:00Z", strategy: .iso8601)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        #expect(calendar.dateComponents(fields, from: first) == calendar.dateComponents(fields, from: second))
        let firstComponents = try trigger(for: first).dateComponents
        let secondComponents = try trigger(for: second).dateComponents
        #expect(try #require(firstComponents.date) == first)
        #expect(try #require(secondComponents.date) == second)
        #expect(firstComponents != secondComponents)
    }

    @Test("主提醒与稍后提醒保持稳定标识、路由内容和单次触发", arguments: [NotificationKind.primary, .snooze])
    func requestKeepsContentAndRouting(_ kind: NotificationKind) throws {
        let date = try Date("2026-09-27T11:30:00Z", strategy: .iso8601)
        let request = request(at: date, kind: kind)
        let systemRequest = LocalNotificationService.makeTaskNotificationRequest(request)
        #expect(systemRequest.identifier == request.identifier)
        #expect(systemRequest.content.title == request.title)
        #expect(systemRequest.content.body == request.body)
        #expect(
            systemRequest.content.userInfo["occurrenceID"] as? String == request.occurrenceID.uuidString.lowercased())
        #expect(systemRequest.content.userInfo["notificationKind"] as? String == kind.rawValue)
        #expect(systemRequest.content.sound != nil)
        #expect(try #require(systemRequest.trigger as? UNCalendarNotificationTrigger).repeats == false)
    }

    private func trigger(for date: Date) throws -> UNCalendarNotificationTrigger {
        try #require(
            LocalNotificationService.makeTaskNotificationRequest(request(at: date)).trigger
                as? UNCalendarNotificationTrigger)
    }

    private func request(at date: Date, kind: NotificationKind = .primary) -> TaskNotificationRequest {
        TaskNotificationRequest(
            occurrenceID: UUID(), kind: kind, title: "边界测试", body: "固定通知内容", scheduledAt: date)
    }
}
